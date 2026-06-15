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
#   RYUK_IMAGE       - Ryuk image to use (default: testcontainers/ryuk:0.14.0)
#   RYUK_PORT        - Host port for Ryuk (default: auto-assigned)
#   CONTAINER_ENGINE - Engine to start: auto|docker|podman|colima|minikube|apple_container (default: auto)
#   CONTAINER_ENGINE_HOST - Container engine socket (auto-detected if not set)
#   TEST_TIMEOUT     - ExUnit timeout in ms (default: 300000)

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

# ── Engine-Specific Startup ──────────────────────────────────────────────────

# When CONTAINER_ENGINE is set to a specific engine (not "auto"), only start
# that engine. This avoids unnecessarily starting Colima when the user wants
# Podman, Docker Desktop, etc.

ensure_engine() {
  local engine="${CONTAINER_ENGINE:-auto}"

  case "$engine" in
    auto|"")
      # Auto mode: try Colima first (existing behaviour)
      ensure_colima
      ;;
    colima)
      info "CONTAINER_ENGINE=colima: starting Colima only"
      ensure_colima
      ;;
    docker)
      info "CONTAINER_ENGINE=docker: ensuring Docker daemon is running"
      if command -v docker &>/dev/null; then
        if docker info >/dev/null 2>&1; then
          success "Docker daemon is already running"
        else
          info "Starting Docker..."
          # Try common ways to start Docker on macOS
          if command -v open &>/dev/null && [[ -e "/Applications/Docker.app" ]]; then
            open -a Docker
            wait_for_docker
          else
            warn "Cannot auto-start Docker. Please start Docker Desktop manually."
          fi
        fi
      else
        error "docker command not found. Is Docker installed?"
        exit 1
      fi
      ;;
    podman)
      info "CONTAINER_ENGINE=podman: ensuring Podman machine is running"
      if command -v podman &>/dev/null; then
        local podman_status
        podman_status=$(podman machine list --format "{{.Running}}" 2>/dev/null | head -1 || echo "false")
        if [[ "$podman_status" == "true" ]]; then
          success "Podman machine is already running"
        else
          info "Starting Podman machine..."
          podman machine start 2>&1 || true
          # Also ensure the socket is available
          podman machine ssh -- systemctl --user start podman.socket 2>/dev/null || true
        fi
      else
        error "podman command not found. Is Podman installed?"
        exit 1
      fi
      ;;
    minikube)
      info "CONTAINER_ENGINE=minikube: ensuring Minikube is running"
      if command -v minikube &>/dev/null; then
        local mk_status
        mk_status=$(minikube status --format="{{.Host}}" 2>/dev/null || echo "Stopped")
        if [[ "$mk_status" == "Running" ]]; then
          success "Minikube is already running"
        else
          info "Starting Minikube..."
          minikube start 2>&1 || true
        fi
      else
        error "minikube command not found. Is Minikube installed?"
        exit 1
      fi
      ;;
    apple_container)
      info "CONTAINER_ENGINE=apple_container: ensuring Apple Container is running"
      if command -v container &>/dev/null; then
        local container_status
        container_status=$(container system status 2>/dev/null || echo "")
        if echo "$container_status" | grep -qi "running"; then
          success "Apple Container is already running"
        else
          info "Starting Apple Container..."
          container system start 2>&1 || true
        fi
      else
        error "container command not found. Is Apple Container installed?"
        exit 1
      fi
      ;;
    *)
      warn "Unknown CONTAINER_ENGINE=\"${engine}\", falling back to auto-detection"
      ensure_colima
      ;;
  esac
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

  # Step 2: Ensure the selected engine is running
  # When CONTAINER_ENGINE is set (and not "auto"), only start that engine.
  # In auto mode, fall back to the existing Colima-first behaviour.
  ensure_engine

  # Step 3: Wait for Docker daemon
  wait_for_docker

  # Step 4: Detect and export Docker socket
  local docker_socket
  docker_socket=$(detect_docker_socket) || {
    error "Could not find Docker socket. Is Docker running?"
    exit 1
  }
  export CONTAINER_ENGINE_HOST="$docker_socket"
  info "CONTAINER_ENGINE_HOST=${CONTAINER_ENGINE_HOST}"
  info "CONTAINER_ENGINE=${CONTAINER_ENGINE:-auto}"

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
