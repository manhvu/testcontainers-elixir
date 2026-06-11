#!/usr/bin/env bash
# script/run_docker_tests.sh
# Runs Docker-dependent tests with automatic Ryuk and Docker environment setup.
#
# Usage:
#   script/run_docker_tests.sh                    # Run all tests (including Docker tests)
#   script/run_docker_tests.sh --setup-only       # Only set up Docker/Ryuk, don't run tests
#   script/run_docker_tests.sh --teardown         # Stop and clean up Ryuk + test containers
#   script/run_docker_tests.sh --include needs_dock  # Run only tests with specific tag
#   script/run_docker_tests.sh test/container/postgres_container_test.exs  # Run specific file
#
# Environment variables:
#   RYUK_IMAGE    - Ryuk image to use (default: testcontainers/ryuk:0.14.0)
#   RYUK_PORT     - Host port for Ryuk (default: auto-assigned)
#   DOCKER_HOST   - Docker daemon socket (auto-detected if not set)
#   TEST_TIMEOUT  - ExUnit timeout in ms (default: 300000)

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

RYUK_IMAGE="${RYUK_IMAGE:-testcontainers/ryuk:0.14.0}"
RYUK_PORT="${RYUK_PORT:-0}"  # 0 = auto-assign
TEST_TIMEOUT="${TEST_TIMEOUT:-300000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RYUK_CONTAINER_NAME="testcontainer_ex-ryuk-$$"

# ── Colors ─────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Helpers ────────────────────────────────────────────────────────────────────

cleanup() {
  local exit_code=$?
  if [[ "${TEARDOWN:-false}" == "true" ]] || [[ "${SETUP_ONLY:-false}" != "true" ]]; then
    teardown_ryuk
  fi
  exit $exit_code
}

trap cleanup EXIT INT TERM

detect_docker_socket() {
  local paths=(
    "/var/run/docker.sock"
    "$HOME/.docker/run/docker.sock"
    "$HOME/.docker/desktop/docker.sock"
    "$HOME/.colima/default/docker.sock"
    "$HOME/.colima/docker.sock"
  )

  for path in "${paths[@]}"; do
    if [[ -S "$path" ]]; then
      echo "unix://$path"
      return 0
    fi
  done

  return 1
}

wait_for_docker() {
  local max_attempts=30
  local attempt=0

  info "Waiting for Docker daemon to be ready..."
  while [[ $attempt -lt $max_attempts ]]; do
    if docker info >/dev/null 2>&1; then
      success "Docker daemon is ready"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  error "Docker daemon did not become ready after ${max_attempts}s"
  return 1
}

ensure_colima() {
  if ! command -v colima &>/dev/null; then
    return 0
  fi

  local status_output
  status_output=$(colima status 2>&1) || true

  if echo "$status_output" | grep -q "colima is running"; then
    info "Colima is already running"
    return 0
  fi

  info "Starting Colima..."
  colima start
  success "Colima started"
}

# ── Ryuk Management ────────────────────────────────────────────────────────────

start_ryuk() {
  info "Starting Ryuk reaper container..."

  # Check if Ryuk is already running
  local existing
  existing=$(docker ps --filter "name=${RYUK_CONTAINER_NAME}" --format "{{.ID}}" 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    warn "Ryuk container already running (${existing}), removing..."
    docker rm -f "$existing" >/dev/null 2>&1 || true
  fi

  # Also check for any orphaned Ryuk containers from previous runs
  local orphans
  orphans=$(docker ps -a --filter "name=testcontainer_ex-ryuk" --format "{{.ID}}" 2>/dev/null || true)
  if [[ -n "$orphans" ]]; then
    info "Cleaning up orphaned Ryuk containers..."
    echo "$orphans" | xargs docker rm -f >/dev/null 2>&1 || true
  fi

  # Pull Ryuk image
  info "Pulling Ryuk image: ${RYUK_IMAGE}"
  docker pull "$RYUK_IMAGE" >/dev/null 2>&1
  success "Ryuk image ready"

  # Determine Docker socket to mount
  local docker_socket
  docker_socket=$(detect_docker_socket) || {
    error "Could not find Docker socket"
    return 1
  }
  info "Using Docker socket: ${docker_socket}"

  # Determine how to give Ryuk access to Docker:
  # - Linux: bind-mount the Docker socket directly
  # - macOS (Colima/Docker Desktop): use host network, because the socket
  #   path is inside a VM that containers can't bind-mount from the host
  local os_type
  os_type=$(uname -s)

  local mount_args=()
  local port_args=()

  if [[ "$os_type" == "Darwin" ]]; then
    # On macOS, Docker runs inside a VM. Use host networking.
    mount_args=("--network" "host")
    # With --network host, -p is ignored by Docker
    port_args=()
  else
    mount_args=("-v" "${docker_socket}:/var/run/docker.sock")
    if [[ "$RYUK_PORT" != "0" ]]; then
      port_args=("-p" "${RYUK_PORT}:8080")
    else
      port_args=("-p" "8080")
    fi
  fi

  # Start Ryuk container
  local ryuk_id
  local docker_run_args=(
    "run" "-d"
    --name "$RYUK_CONTAINER_NAME"
    --restart unless-stopped
    "${mount_args[@]}"
    --privileged
    "$RYUK_IMAGE"
  )

  # Only add port args on non-macOS
  if [[ "$os_type" != "Darwin" ]]; then
    docker_run_args+=("${port_args[@]}")
  fi

  ryuk_id=$(docker "${docker_run_args[@]}" 2>&1)

  if [[ $? -ne 0 ]] || [[ -z "$ryuk_id" ]]; then
    error "Failed to start Ryuk container"
    return 1
  fi

  success "Ryuk container started: ${ryuk_id:0:12}"

  # Wait for Ryuk to be ready
  info "Waiting for Ryuk to be ready..."
  local max_attempts=30
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    # Check if container is still running
    if ! docker ps --filter "id=${ryuk_id}" --format "{{.ID}}" 2>/dev/null | grep -q .; then
      error "Ryuk container exited unexpectedly"
      docker logs "$ryuk_id" 2>&1 || true
      return 1
    fi

    # On macOS with --network host, Ryuk is accessible on localhost:8080
    # On Linux, we need to check the mapped port
    local check_port
    if [[ "$os_type" == "Darwin" ]]; then
      check_port=8080
    else
      check_port=$(docker port "$RYUK_CONTAINER_NAME" 8080 2>/dev/null | cut -d: -f2 || echo "")
    fi

    if [[ -n "$check_port" ]] && echo -e "GET / HTTP/1.0\r\n\r\n" | nc -w 2 127.0.0.1 "$check_port" 2>/dev/null | grep -q "HTTP"; then
      success "Ryuk is ready on port ${check_port}"
      export RYUK_HOST_PORT="$check_port"
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 1
  done

  warn "Ryuk health check timed out, but container is running. Tests may still work."
  return 0
}

teardown_ryuk() {
  local ryuk_id
  ryuk_id=$(docker ps --filter "name=${RYUK_CONTAINER_NAME}" --format "{{.ID}}" 2>/dev/null || true)

  if [[ -n "$ryuk_id" ]]; then
    info "Stopping Ryuk container: ${ryuk_id:0:12}"
    docker stop "$ryuk_id" >/dev/null 2>&1 || true
    docker rm "$ryuk_id" >/dev/null 2>&1 || true
    success "Ryuk container removed"
  fi
}

# ── Test Execution ─────────────────────────────────────────────────────────────

run_tests() {
  local test_args=("$@")

  info "Running tests..."
  info "  Docker socket: $(detect_docker_socket || echo 'not found')"
  info "  Ryuk: running (${RYUK_CONTAINER_NAME})"
  info "  Timeout: ${TEST_TIMEOUT}ms"

  cd "$PROJECT_DIR"

  # Run tests without excluding needs_dock/dood_limitation
  local mix_cmd=(mix test --exclude flaky --timeout "$TEST_TIMEOUT")

  if [[ ${#test_args[@]} -gt 0 ]]; then
    mix_cmd+=("${test_args[@]}")
  fi

  info "Command: ${mix_cmd[*]}"
  echo ""
  "${mix_cmd[@]}"
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  local setup_only=false
  local teardown_only=false
  local test_args=()

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --setup-only)
        setup_only=true
        shift
        ;;
      --teardown|--cleanup)
        teardown_only=true
        TEARDOWN=true
        shift
        ;;
      --include)
        test_args+=("--include" "$2")
        shift 2
        ;;
      --help|-h)
        sed -n '2,15p' "$0" | sed 's/^# \?//'
        exit 0
        ;;
      *)
        test_args+=("$1")
        shift
        ;;
    esac
  done

  if [[ "$teardown_only" == "true" ]]; then
    teardown_ryuk
    # Also clean up any test containers
    info "Cleaning up test containers..."
    docker ps -a --filter "label=org.testcontainer_ex" --format "{{.ID}}" 2>/dev/null | \
      xargs -r docker rm -f >/dev/null 2>&1 || true
    success "Cleanup complete"
    exit 0
  fi

  # Step 1: Ensure Docker is available
  if ! command -v docker &>/dev/null; then
    error "Docker is not installed or not in PATH"
    exit 1
  fi

  # Step 2: Ensure Colima is running (if applicable)
  ensure_colima

  # Step 3: Wait for Docker daemon
  wait_for_docker

  # Step 4: Detect and export Docker socket
  local docker_socket
  docker_socket=$(detect_docker_socket) || {
    error "Could not find Docker socket. Is Docker running?"
    exit 1
  }
  export DOCKER_HOST="$docker_socket"
  info "DOCKER_HOST=${DOCKER_HOST}"

  # Step 5: Start Ryuk
  SETUP_ONLY="$setup_only"
  start_ryuk

  if [[ "$setup_only" == "true" ]]; then
    info "Setup complete. Ryuk is running."
    info "Run tests with: mix test --include needs_dock"
    info "Teardown with: $0 --teardown"
    exit 0
  fi

  # Step 6: Run tests
  run_tests "${test_args[@]}"
}

main "$@"
