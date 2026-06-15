# TestcontainerEx

[![Hex.pm](https://img.shields.io/hexpm/v/testcontainer_ex.svg)](https://hex.pm/packages/testcontainer_ex)

> **Status:** Early development & unstable. Not yet ready for production use.

Forked from [testcontainers-elixir](https://github.com/testcontainers/testcontainers-elixir), rework and add support for Podman, Minikube, and Colima, a `.env` file for project-local Docker host configuration, a hand-written Docker Engine API client replacing the auto-generated one, third-party registry support (quay.io, ghcr.io, gcr.io, and more), and a clean architecture refactor.

TestcontainerEx is an Elixir library that supports ExUnit tests, providing lightweight, throwaway instances of common databases, Selenium web browsers, or anything else that can run in a Docker or Podman container.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Setup with .env](#quick-setup-with-env)
- [Usage](#usage)
- [Container Info & Connection Helpers](#container-info--connection-helpers)
- [Wait Strategies](#wait-strategies)
- [Structured Logging](#structured-logging)
- [Telemetry & Observability](#telemetry--observability)
- [Debugging](#debugging)
- [Podman Support](#podman-support)
- [Minikube Support](#minikube-support)
- [Colima Support](#colima-support)
- [Docker Host Resolution](#docker-host-resolution)
- [Configuration](#configuration)
- [API Documentation](#api-documentation)
- [Guides](#guides)
- [Windows support](#windows-support)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

## Prerequisites

Before you begin, ensure you have met the following requirements:
- You have installed the latest version of [Elixir](https://elixir-lang.org/install.html)
- You have a Docker or Podman runtime installed
- You are familiar with Elixir and container basics

## Installation

To add TestcontainerEx to your project, follow these steps:

1. Add `testcontainer_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:testcontainer_ex, "~> X.X", only: [:test, :dev]}
  ]
end
```

Replace X.X with the current major and minor version.

### Optional dependencies

TestcontainerEx includes these runtime dependencies automatically:

| Dependency | Purpose |
|-----------|--------|
| `:telemetry` | Observability events for container lifecycle timing |
| `:recon` | Advanced runtime debugging (dev/test only) |

No additional configuration is needed — they are started automatically.

2. Run mix deps.get

3. Add the following to test/test_helper.exs

```elixir
TestcontainerEx.start_link()
```

## Quick Setup with .env

TestcontainerEx needs to know where your Docker/Podman daemon is listening. The easiest way is to use a `.env` file in your project root — no shell exports or profile changes needed.

### Step 1: Copy the template

```bash
cp .env.example .env
```

### Step 2: Uncomment the right CONTAINER_ENGINE_HOST

Open `.env` and uncomment the line that matches your container runtime:

| Runtime | Line to uncomment |
|---------|------------------|
| **Colima** (macOS/Linux) | `CONTAINER_ENGINE_HOST=unix://$HOME/.colima/default/docker.sock` |
| **Docker Desktop** (macOS) | `CONTAINER_ENGINE_HOST=unix://$HOME/.docker/run/docker.sock` |
| **Docker Desktop** (Windows) | `CONTAINER_ENGINE_HOST=unix://$HOME/.docker/desktop/docker.sock` |
| **Docker Engine** (Linux) | `CONTAINER_ENGINE_HOST=unix:///var/run/docker.sock` |
| **Podman** (Linux rootless) | `CONTAINER_ENGINE_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock` |
| **Minikube** | `CONTAINER_ENGINE_HOST=tcp://$(minikube ip):2375` |
| **Remote Docker** (TCP) | `CONTAINER_ENGINE_HOST=tcp://192.168.1.100:2375` |

> **Tip:** Use `$HOME` instead of hardcoded paths — it expands to your home directory on any OS. For Podman, `$XDG_RUNTIME_DIR` is typically `/run/user/<uid>`.

### Step 3: Run your tests

```bash
mix test
```

That's it! The `.env` file is read automatically by the Dotenv connection strategy.

### Selecting a specific engine

You can set `CONTAINER_ENGINE` to control which engine is started and used. This is useful when you have multiple engines installed and want to target a specific one:

```bash
# Use Docker Desktop (doesn't start Colima)
CONTAINER_ENGINE=docker mix test

# Use Podman
CONTAINER_ENGINE=podman mix test

# Use Minikube
CONTAINER_ENGINE=minikube mix test

# Auto-detect (default behavior)
CONTAINER_ENGINE=auto mix test
```

When `CONTAINER_ENGINE` is set to a specific engine, TestcontainerEx only starts/checks that engine — it won't start Colima or scan for other engines. See the [Runtime Engine Selection guide](guides/runtime_engine_selection.md) for details.

### How it works

When TestcontainerEx starts, it resolves the container engine host using this priority order:

1. `CONTAINER_ENGINE` environment variable — if set to a specific engine (`docker`, `podman`, `colima`, `minikube`, `apple_container`), only that engine's strategies are tried
2. `~/.testcontainer_ex.properties` (global user config)
3. `CONTAINER_ENGINE_HOST` environment variable (shell/profile)
4. **`.env` file** in project root ← this is what we just set up (checks `CONTAINER_ENGINE_HOST` first, then `DOCKER_HOST`)
5. `CONTAINER_HOST` environment variable (Podman)
6. Minikube auto-detection
7. Socket path auto-scan

The `.env` file is **only** consulted when `CONTAINER_ENGINE_HOST` is already set in your shell. Shell settings always win.

### .env file format

```bash
# Container engine host (required — uncomment one)
CONTAINER_ENGINE_HOST=unix://$HOME/.colima/default/docker.sock

# TestcontainerEx options (optional)
TESTCONTAINERS_RYUK_DISABLED=false          # Disable auto-cleanup
TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED=false  # Privileged Ryuk (SELinux)
TESTCONTAINERS_PULL_POLICY=missing          # "missing", "always", or "never"
TESTCONTAINERS_REUSE_ENABLE=false           # Reuse containers across runs
TESTCONTAINERS_HOST_OVERRIDE=               # Override connection host
```

Environment variables with the `TESTCONTAINERS_` prefix are automatically converted to dotted property keys:

| Environment Variable | Property Key |
|---------------------|-------------|
| `TESTCONTAINERS_RYUK_DISABLED` | `ryuk.disabled` |
| `TESTCONTAINERS_PULL_POLICY` | `pull.policy` |
| `TESTCONTAINERS_REUSE_ENABLE` | `testcontainer_ex.reuse.enable` |

> **Security:** The `.env` file is in `.gitignore` by default so machine-specific paths are never committed. A `.env.example` template is provided for sharing with your team.

## Usage

This section explains how to use the TestcontainerEx library in your own project.

### Basic usage

You can use generic container api, where you have to define everything yourself:

```elixir
{:ok, _} = TestcontainerEx.start_link()
config = %TestcontainerEx.Container{image: "redis:5.0.3-alpine"}
{:ok, container} = TestcontainerEx.start_container(config)
```

Or you can use one of many predefined containers like `RedisContainer`, that has waiting strategies among other things defined up front with good defaults:

```elixir
{:ok, _} = TestcontainerEx.start_link()
config = TestcontainerEx.RedisContainer.new()
{:ok, container} = TestcontainerEx.start_container(config)
```

If you want to use a predefined container, such as `RedisContainer`, with an alternative image, for example, `valkey/valkey`, it's possible:

```elixir
{:ok, _} = TestcontainerEx.start_link()
config =
  TestcontainerEx.RedisContainer.new()
  |> TestcontainerEx.RedisContainer.with_image("valkey/valkey:latest")
  |> TestcontainerEx.RedisContainer.with_check_image("valkey/valkey")
{:ok, container} = TestcontainerEx.start_container(config)
```

### ExUnit tests

Given you have added TestcontainerEx.start_link() to test_helper.exs:

```elixir
setup 
  config = TestcontainerEx.RedisContainer.new()
  {:ok, container} = TestcontainerEx.start_container(config)
  ExUnit.Callbacks.on_exit(fn -> TestcontainerEx.stop_container(container.container_id) end)
  {:ok, %{redis: container}}
end
```

there is a macro that can simplify this down to a oneliner:

```elixir
import TestcontainerEx.ExUnit

container(:redis, TestcontainerEx.RedisContainer.new())
```

### Run tests in a Phoenix project (or any project for that matter)

To run/wrap testcontainer_ex around a project use the testcontainer_ex.run task.

`mix testcontainer_ex.run [sub_task] [--database postgres|mysql] [--db-volume VOLUME]`

to use postgres you can just run

`mix testcontainer_ex.run test` since postgres is default and test is the default sub-task.

#### Examples:

```bash
# Run tests with PostgreSQL (default)
MIX_ENV=test mix testcontainer_ex.run test

# Run tests with MySQL
MIX_ENV=test mix testcontainer_ex.run test --database mysql

# Run Phoenix server with PostgreSQL and persistent volume
mix testcontainer_ex.run phx.server --database postgres --db-volume my_postgres_data

# Run tests with MySQL and persistent volume
MIX_ENV=test mix testcontainer_ex.run test --database mysql --db-volume my_mysql_data

# Start Phoenix server with containerized DB (will keep running until stopped)
mix testcontainer_ex.run phx.server --database postgres --db-volume my_dev_data
```

#### Persistent Volumes

The `--db-volume` parameter allows you to specify a persistent volume for database data. This ensures that your database data persists between container restarts. The volume name you provide will be used to create a Docker volume that gets mounted to the appropriate database data directory:

- **PostgreSQL**: Volume is mounted to `/var/lib/postgresql/data`
- **MySQL**: Volume is mounted to `/var/lib/mysql`

This is particularly useful when you want to maintain database state across test runs or development sessions.

#### Configuration (runtime.exs)

Instead of editing dev.exs or test.exs, you can let testcontainer_ex set `DATABASE_URL` and use it from `config/runtime.exs` for dev and test:

```elixir
# config/runtime.exs

if config_env() in [:dev, :test] do
  if url = System.get_env("DATABASE_URL") do
    config :my_app, MyApp.Repo,
      url: url,
      pool: Ecto.Adapters.SQL.Sandbox,
      show_sensitive_data_on_connection_error: true,
      pool_size: 10
  end
end
```

This allows you to run your Phoenix server or tests with a containerized database without changing dev.exs or test.exs (remember to set MIX_ENV when running tests):

```bash
# Start Phoenix server with PostgreSQL container
mix testcontainer_ex.run phx.server --database postgres

# Start Phoenix server with MySQL container
mix testcontainer_ex.run phx.server --database mysql

# Start with persistent data
mix testcontainer_ex.run phx.server --database postgres --db-volume my_dev_data
```

Activate reuse of database containers started by mix task with adding `testcontainer_ex.reuse.enable=true` in `~/.testcontainer_ex.properties`. This is experimental.

You can pass arguments to the sub-task by appending them after `--`. For example, to pass arguments to mix test:

`MIX_ENV=test mix testcontainer_ex.run test -- --exclude flaky --stale`

In the example above we are running tests while excluding flaky tests and using the --stale option.

Note: MIX_ENV is not overridden by the run task. For tests, set it explicitly in the shell:

`MIX_ENV=test mix testcontainer_ex.run test`

### Logging

TestcontainerEx use the standard Logger, see https://hexdocs.pm/logger/Logger.html.

## Container Info & Connection Helpers

The `TestcontainerEx.Container.Info` module provides ready-to-use connection options for common databases and services. No more manually extracting host, port, username, and password from the container environment.

### Quick connection setup

```elixir
{:ok, container} = TestcontainerEx.start_container(TestcontainerEx.PostgresContainer.new())

# Get Postgrex-compatible connection options
opts = TestcontainerEx.Container.Info.pg_connect_opts(container)
# => [hostname: "localhost", port: 55123, username: "test", password: "test", database: "test"]

{:ok, conn} = Postgrex.start_link(opts)
```

### Available helpers

| Function | Returns | Use with |
|----------|---------|----------|
| `pg_connect_opts/2` | Keyword list | `Postgrex.start_link/1` |
| `mysql_connect_opts/2` | Keyword list | `MyXQL.start_link/1` |
| `redis_url/1` | `"redis://host:port/"` | `Redix.start_link/1` |
| `mongo_url/1` | `"mongodb://user:pass@host:port/db"` | `Mongo.start_link/1` |
| `amqp_url/1` | `"amqp://user:pass@host:port"` | `AMQP.Connection.open/1` |
| `url/3` | `"scheme://host:port"` | Any TCP service |
| `host/1` | Host string | Manual connections |
| `port/2` | Mapped port integer | Manual connections |

All `*_connect_opts` functions accept an optional second argument for overrides:

```elixir
# Override the database name
opts = TestcontainerEx.Container.Info.pg_connect_opts(container, database: "my_other_db")
```

### Generic URL builder

```elixir
# Build a URL for any TCP service
url = TestcontainerEx.Container.Info.url(container, 9042, "cassandra")
# => "cassandra://localhost:55124"
```

## Wait Strategies

Wait strategies determine when a container is considered "ready". TestcontainerEx provides four built-in strategies:

| Strategy | Ready when... | Module |
|----------|---------------|--------|
| **Port** | A TCP port accepts connections | `PortWaitStrategy` |
| **HTTP** | An HTTP request succeeds | `HttpWaitStrategy` |
| **Log** | A log line matches a regex | `LogWaitStrategy` |
| **Command** | A command exits with code 0 | `CommandWaitStrategy` |

### Using the unified `TestcontainerEx.Wait` module

Instead of remembering each strategy module, use the convenience aliases:

```elixir
alias TestcontainerEx.Wait

# Port wait — wait for port 5432 to accept connections
Wait.port("localhost", 5432, 60_000)

# HTTP wait — wait for an HTTP 200 from /health
Wait.http("/health", 8080, status_code: 200)

# Log wait — wait for a specific log line
Wait.log(~r/Server started/, 60_000)

# Command wait — wait for a command to succeed
Wait.command(["pg_isready", "-U", "test"], 60_000)
```

### Combining multiple strategies

```elixir
import TestcontainerEx.Container

config =
  new("my-app:latest")
  |> with_exposed_port(8080)
  |> with_waiting_strategies([
    TestcontainerEx.LogWaitStrategy.new(~r/Application started/, 30_000),
    TestcontainerEx.HttpWaitStrategy.new("/health", 8080, status_code: 200)
  ])
```

## Structured Logging

The `TestcontainerEx.Log` module wraps Elixir's `Logger` with contextual metadata so log lines are easy to filter and correlate with specific containers.

```elixir
import TestcontainerEx.Log

# These automatically include :testcontainer_ex, :container_id, :image metadata
log_info("Container started", container_id: id, image: "postgres:15")
log_debug("Pulling image", image: "redis:7")
log_warning("Ryuk disabled", reason: :config)
log_error("Failed to start", container_id: id, error: reason)
```

### Configuring log output

In `config/dev.exs`, the logger is configured to include TestcontainerEx metadata:

```elixir
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:testcontainer_ex, :container_id, :image, :session_id, :engine]
```

This produces output like:

```
19:13:16.588 testcontainer_ex=true image=redis:7 [info] Pulling image
19:13:17.123 testcontainer_ex=true container_id=abc123 [info] Container started
```

### Available functions

| Function | Level |
|----------|-------|
| `info/2` | `:info` |
| `debug/2` | `:debug` |
| `warning/2` | `:warning` |
| `error/2` | `:error` |
| `log/3` | Custom level |

## Telemetry & Observability

TestcontainerEx emits `:telemetry` events at key lifecycle points, so you can measure container start times, track pull durations, and integrate with monitoring tools.

### Events

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:testcontainer_ex, :container, :start]` | `duration`, `monotonic_time` | `image` |
| `[:testcontainer_ex, :container, :stop]` | `duration`, `monotonic_time` | `container_id` |
| `[:testcontainer_ex, :network, :create]` | `duration`, `monotonic_time` | `network_name` |
| `[:testcontainer_ex, :network, :remove]` | `duration`, `monotonic_time` | `network_name` |

Each event also emits `[:start]`, `[:stop]`, and `[:exception]` suffix variants for span tracking.

### Attaching a handler

```elixir
:telemetry.attach(
  "my-container-metrics",
  [:testcontainer_ex, :container, :start],
  fn _name, measurements, _meta, _config ->
    # Log or record metrics
    duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)
    IO.puts("Container started in #{duration_ms}ms")
  end,
  nil
)
```

### With Telemetry.Metrics

```elixir
# In your metrics supervisor
[
  Metrics.summary("testcontainer_ex.container.start.duration",
    unit: {:native, :millisecond},
    description: "Container start time"
  ),
  Metrics.summary("testcontainer_ex.network.create.duration",
    unit: {:native, :millisecond},
    description: "Network creation time"
  )
]
```

### Manual events

You can also emit custom telemetry events:

```elixir
TestcontainerEx.Telemetry.event(
  [:testcontainer_ex, :wait, :strategy],
  %{duration: elapsed},
  %{strategy: :port_wait, container_id: id}
)
```

## Debugging

TestcontainerEx provides several debugging tools for use from `iex -S mix` or when troubleshooting failing tests.

### Quick status check

```elixir
iex> TestcontainerEx.debug_status()
%{
  connected: true,
  engine: :docker,
  running_in_container: false,
  host: "localhost",
  container_ip_mode: false
}
```

### Inspect a running container

```elixir
iex> {:ok, container} = TestcontainerEx.start_container(redis)
iex> TestcontainerEx.debug_inspect(container)
%{
  container_id: "abc123...",
  image: "redis:7.2-alpine",
  ports: [{6379, 55123}],
  ip_address: "172.17.0.3",
  environment: %{},
  labels: %{...},
  reuse: false,
  wait_strategies: [TestcontainerEx.CommandWaitStrategy]
}
```

### One-line summary

```elixir
iex> TestcontainerEx.debug_summarize(container)
"redis:7.2-alpine [abc123] ports: 6379->55123 ip: 172.17.0.3"
```

### List tracked resources

```elixir
iex> TestcontainerEx.debug_list_containers()
["abc123...", "def456..."]

iex> TestcontainerEx.debug_list_networks()
["my-test-network"]
```

### Using the Debug module directly

```elixir
iex> TestcontainerEx.Debug.status()           # Same as debug_status()
iex> TestcontainerEx.Debug.inspect_container(c)  # Same as debug_inspect(c)
iex> TestcontainerEx.Debug.summarize(c)       # Same as debug_summarize(c)
```

### Recon (advanced runtime inspection)

For deeper debugging, TestcontainerEx includes `:recon` in dev/test environments. The `TestcontainerEx.Recon` module provides Elixir-friendly wrappers:

```elixir
# View the GenServer's internal state
iex> TestcontainerEx.Recon.server_state()
%{conn: _, containers: _, networks: _, ...}

# Get a readable summary of tracked resources
iex> TestcontainerEx.Recon.resource_summary()
%{
  container_count: 2,
  containers: ["abc123", "def456"],
  network_count: 1,
  networks: ["my-network"],
  image_count: 2,
  connected: true,
  docker_hostname: "localhost"
}

# Top processes by memory
iex> TestcontainerEx.Recon.top_processes(5)

# Memory allocation breakdown
iex> TestcontainerEx.Recon.memory()
```

### Custom Inspect for containers

Container configs now have a custom `Inspect` implementation for readable IEx output:

```elixir
iex> container
#Container<[image: "postgres:15-alpine", container_id: "abc123", ports: "5432->55123", ip_address: "172.17.0.3", network: nil, reuse: false]>
```

Instead of the raw struct dump, you get a focused summary with image, ID, ports, and network info.

## Podman Support

TestcontainerEx Elixir supports [Podman](https://podman.io/) as a drop-in replacement for Docker. Podman is daemonless, rootless by default, and compatible with the Docker Engine API.

### Quick Start with Podman

1. **Install Podman** (4.0 or later recommended for `podman compose` support):

   ```bash
   # Fedora / RHEL
   sudo dnf install podman

   # Ubuntu
   sudo apt-get install podman

   # macOS
   brew install podman
   ```

2. **Start the Podman socket** (required for the Docker-compatible API):

   ```bash
   # Rootless (recommended)
   systemctl --user enable --now podman.socket

   # Or set the socket path manually
   export CONTAINER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
   ```

3. **Run your tests** — everything else works the same as with Docker:

   ```bash
   MIX_ENV=test mix test
   ```

### Environment Variables

Podman uses `CONTAINER_HOST`:

| Variable | Description |
|----------|-------------|
| `CONTAINER_ENGINE_HOST` | Primary env var for any container engine |
| `CONTAINER_HOST` | Podman socket path |

All three are recognized. `CONTAINER_ENGINE_HOST` takes precedence, then `CONTAINER_HOST`.

### Compose Support

Docker Compose files work with Podman through `podman compose` (built into Podman 4+) or `podman-compose`. The compose provider is auto-detected:

1. `CONTAINER_COMPOSE_PROVIDER` or `PODMAN_COMPOSE_PROVIDER` env var (highest priority)
2. `podman compose` (if `podman` supports the `compose` subcommand)
3. `docker` (default fallback)

```bash
# Use podman-compose explicitly
export CONTAINER_COMPOSE_PROVIDER=podman-compose
MIX_ENV=test mix test
```

### Rootless Podman with SELinux

On distributions that enforce SELinux (e.g. Fedora), the Ryuk reaper container may be denied write access to the Podman socket unless it runs privileged. Enable it with:

```bash
# Environment variable
export TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED=true

# Or in ~/.testcontainer_ex.properties
echo "ryuk.container.privileged=true" >> ~/.testcontainer_ex.properties
```

### Podman Socket Paths

The library automatically detects Podman sockets at these locations:

- `$XDG_RUNTIME_DIR/podman/podman.sock` (rootless Podman — typically `/run/user/<uid>/podman/podman.sock`)
- `$XDG_RUNTIME_DIR/containers/podman.sock`
- `$XDG_RUNTIME_DIR/docker.sock`
- `/var/run/docker.sock` (rootful Podman with Docker compatibility)
- `$HOME/.colima/default/docker.sock` (Colima with Podman runtime)

> **Tip:** Set `CONTAINER_ENGINE_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock` in your `.env` file for rootless Podman.

See [Docker Host Resolution](#docker-host-resolution) for the full list of detected socket paths.

## Minikube Support

TestcontainerEx works with [minikube](https://minikube.sigs.k8s.io/)'s Docker daemon. Minikube runs a Docker (or Podman) daemon inside a VM, and TestcontainerEx can connect to it via TCP with TLS.

### Quick Start with Minikube

1. **Start minikube** (Docker driver):

   ```bash
   minikube start --driver=docker
   ```

2. **Point TestcontainerEx at minikube's Docker daemon:**

   ```bash
   eval $(minikube docker-env)
   MIX_ENV=test mix test
   ```

   The `minikube docker-env` command sets `CONTAINER_ENGINE_HOST`, `DOCKER_CERT_PATH`, and `DOCKER_TLS_VERIFY`
   environment variables. TestcontainerEx reads all of these automatically.

3. **Or use the none driver** (runs directly on the host):

   ```bash
   minikube start --driver=none
   MIX_ENV=test mix test
   ```

   With the none driver, minikube uses the host's Docker socket directly, so no
   extra configuration is needed.

### Auto-Detection

TestcontainerEx automatically detects a minikube environment by checking for:

- The `MINIKUBE_ACTIVE_DOCKERD` environment variable
- The `MINIKUBE_PROFILE` environment variable
- A `CONTAINER_ENGINE_HOST` or `DOCKER_HOST` value in the `192.168.49.0/24` subnet (minikube's default)
- The presence of the `minikube` binary (evaluates `minikube docker-env`)

When detected, the engine is logged as `minikube` during initialization.

### TLS Certificates

Minikube's Docker daemon uses TLS. The certificates are stored in
`~/.minikube/certs/` by default. TestcontainerEx automatically loads `ca.pem`,
`cert.pem`, and `key.pem` from the directory specified by `DOCKER_CERT_PATH`
(which `minikube docker-env` sets).

### Running Tests Inside a Minikube Pod

If your tests run inside a Kubernetes pod managed by minikube (e.g., in a CI
pipeline), TestcontainerEx detects the container environment via:

- `/.dockerenv` file
- `/var/run/secrets/kubernetes.io` directory
- `/proc/1/cgroup` containing `kubepods`

In this case, you may need to mount the Docker socket into your pod and set
`TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE` to the mounted path.

## Colima Support

TestcontainerEx works with [Colima](https://github.com/abiosoft/colima), a lightweight Docker/Podman runtime for macOS and Linux. Colima runs a Linux VM with Docker or Podman inside and exposes a Unix socket on the host.

### Quick Start with Colima

1. **Install and start Colima:**

   ```bash
   brew install colima
   colima start
   ```

2. **Run your tests:**

   ```bash
   MIX_ENV=test mix test
   ```

   TestcontainerEx automatically detects the Colima socket at `$HOME/.colima/default/docker.sock`.

### Specifying the Colima socket explicitly

If auto-detection does not work (e.g. you use a named Colima profile), you can set the socket path via any of the standard configuration methods:

```bash
# Environment variable
export CONTAINER_ENGINE_HOST=unix://$HOME/.colima/default/docker.sock

# Or in ~/.testcontainer_ex.properties
echo "tc.host=unix://$HOME/.colima/default/docker.sock" >> ~/.testcontainer_ex.properties

# Or in a project .env file
echo "CONTAINER_ENGINE_HOST=unix://$HOME/.colima/default/docker.sock" >> .env
```

### Detected Socket Path

The library automatically detects the Colima socket at:

- `$HOME/.colima/default/docker.sock` (default profile)

For named profiles, the socket is at `$HOME/.colima/<profile>/docker.sock` — set `CONTAINER_ENGINE_HOST` explicitly for these.

See [Docker Host Resolution](#docker-host-resolution) for the full list of detected socket paths.

## Docker Host Resolution

TestcontainerEx resolves the container engine host by trying several strategies in order. The first strategy that succeeds wins.

### Resolution order

| Priority | Strategy | Source | Notes |
|----------|----------|--------|-------|
| 0 | **Engine selection** | `CONTAINER_ENGINE` env var | If set to `docker`/`podman`/`colima`/`minikube`/`apple_container`, restricts which strategies below are tried. `auto` or unset = try all. |
| 1 | **Properties file** | `~/.testcontainer_ex.properties` | Checks `tc.host`, then `docker.host` |
| 2 | **Environment variable** | `CONTAINER_ENGINE_HOST` | Primary env var (shell/profile) |
| 3 | **Fallback env var** | `DOCKER_HOST` | Backward-compatible fallback |
| 4 | **`.env` file** | `.env` in project root | Checks `CONTAINER_ENGINE_HOST` first, then `DOCKER_HOST` |
| 5 | **Container env var** | `CONTAINER_HOST` | Podman equivalent |
| 6 | **Minikube** | `minikube docker-env` | Auto-detected when minikube is available |
| 7 | **Socket scan** | Well-known paths | Docker Desktop, Docker Engine, Podman, Colima sockets |

### `.env` file

You can place a `.env` file in your project root to configure the container engine host without modifying your shell profile. A `.env.example` template is provided — copy it and uncomment the right line:

```bash
cp .env.example .env
# Edit .env and uncomment the CONTAINER_ENGINE_HOST for your runtime
```

```bash
# .env
CONTAINER_ENGINE_HOST=unix://$HOME/.colima/default/docker.sock
```

This is especially useful for Colima users on macOS, where the socket path is not in the default search list.

> **Tip:** Use `$HOME` in your `.env` file instead of hardcoded paths like `/Users/yourname/...`. The `$HOME` variable expands automatically on any OS.

The `.env` file uses simple `KEY=VALUE` syntax, one per line. Lines starting with `#` are comments. You can also set TestcontainerEx options:

```bash
# .env — project-local container engine host config
CONTAINER_ENGINE_HOST=unix://$HOME/.colima/default/docker.sock
TESTCONTAINERS_PULL_POLICY=missing
TESTCONTAINERS_REUSE_ENABLE=false
```

> **Note:** The `.env` file is only consulted when neither `CONTAINER_ENGINE_HOST` nor `DOCKER_HOST` is already set in your environment. Shell/profile settings always take precedence.
>
> **Security:** `.env` is in `.gitignore` by default. Use `.env.example` for sharing with your team.

### Socket auto-detection

When no explicit host is configured, TestcontainerEx scans these socket paths:

| Path | Runtime |
|------|---------|
| `/var/run/docker.sock` | Docker Engine (Linux) |
| `$HOME/.docker/run/docker.sock` | Docker Desktop (macOS/Windows) |
| `$HOME/.docker/desktop/docker.sock` | Docker Desktop (alternate) |
| `$HOME/.colima/default/docker.sock` | Colima (default profile) |
| `$HOME/.colima/<profile>/docker.sock` | Colima (named profile) |
| `$XDG_RUNTIME_DIR/podman/podman.sock` | Podman (rootless) |
| `$XDG_RUNTIME_DIR/containers/podman.sock` | Podman (alternate) |
| `$XDG_RUNTIME_DIR/docker.sock` | Generic XDG socket |
| `/var/run/minikube/docker.sock` | Minikube |

> **Tip:** `$HOME` expands to your home directory. `$XDG_RUNTIME_DIR` is typically `/run/user/<uid>` on Linux. Both work in `.env` files and shell exports.

Only paths that exist on disk are probed. Each candidate is validated with a ping to the Docker Engine API.

## Configuration

### Pull policy

By default, TestcontainerEx pulls an image only when it isn't already present in the local Docker daemon. This avoids Docker Hub rate limits on repeated test runs. The policy per container can be overridden:

```elixir
alias TestcontainerEx.{Container, PullPolicy}

# pulled only if not present locally (default)
%Container{image: "redis:7", pull_policy: PullPolicy.pull_if_missing()}

# always pull, bypassing any cached image
%Container{image: "redis:7", pull_policy: PullPolicy.always_pull()}

# never pull; expect the image to exist locally
%Container{image: "redis:7", pull_policy: PullPolicy.never_pull()}

# conditional pull; pass a 2-arity function
%Container{
  image: "redis:7",
  pull_policy: PullPolicy.pull_condition(fn _config, _conn -> should_pull?() end)
}
```

The global default can also be set in `~/.testcontainer_ex.properties` via `pull.policy` (`missing` — default, `always`, or `never`).

### Naming containers

Give a container a stable name so other containers on the same network can reference it by name:

```elixir
TestcontainerEx.Container.new("postgres:16")
|> TestcontainerEx.Container.with_name("my-postgres")
```

The name is passed straight through to Docker's `/containers/create` as the `name` query parameter, so the usual Docker rules apply (must be unique on the daemon, `[a-zA-Z0-9][a-zA-Z0-9_.-]+`).

### Private registries

TestcontainerEx supports **any Docker-compatible registry** — Docker Hub, Quay.io, GitHub Container Registry (ghcr.io), Google Container Registry (gcr.io), GitLab Registry, Amazon ECR, Microsoft Container Registry, NVIDIA NGC, and more.

If the image lives on a registry that requires authentication, TestcontainerEx automatically resolves credentials from the user's Docker config on image pull. The lookup order is:

1. `Container.auth` if set explicitly — always wins.
2. The `auths` map in `$DOCKER_CONFIG/config.json` (or `~/.docker/config.json` if `DOCKER_CONFIG` is unset). The registry host is extracted from the image reference and matched against entries in the map.
3. Anonymous pull.

The registry host is automatically extracted from the image reference:

| Image reference | Resolved registry |
|----------------|-------------------|
| `nginx` | `https://index.docker.io/v1/` (Docker Hub) |
| `quay.io/org/image` | `quay.io` |
| `ghcr.io/org/image` | `ghcr.io` |
| `gcr.io/project/image` | `gcr.io` |
| `registry.gitlab.com/org/image` | `registry.gitlab.com` |
| `myregistry:5000/image` | `myregistry:5000` |

Only the `auths` map is consulted; credential-helper binaries (`credsStore`, `credHelpers`) are not invoked. If an auto-resolved credential is rejected with a 4xx, the pull is retried once anonymously to keep stale entries in `config.json` from breaking pulls that would otherwise succeed without auth.

To log in before running tests:

```bash
docker login quay.io
docker login ghcr.io
docker login gcr.io
docker login myregistry.example.com
```

### TLS-secured Docker hosts

TestcontainerEx recognizes TLS-secured Docker daemons out of the box. Point it at one with:

- `CONTAINER_ENGINE_HOST=https://docker.example.internal:2376`, or
- `CONTAINER_ENGINE_HOST=tcp://docker.example.internal:2376` plus `DOCKER_TLS_VERIFY=1`.

The client looks for `ca.pem`, `cert.pem`, and `key.pem` in the directory named by `DOCKER_CERT_PATH` (or `~/.docker` if unset); whichever files are present are used to build the SSL context, matching the Docker CLI's behavior. When `DOCKER_TLS_VERIFY` is unset, peer verification is disabled and a warning is logged.

### Ryuk under SELinux / rootless Docker or Podman

On distributions that enforce SELinux (for example Fedora), the Ryuk reaper container may be denied write access to the Docker/Podman socket unless it runs privileged. This is especially common with rootless Podman. Enable it with either:

- the `ryuk.container.privileged=true` property in `~/.testcontainer_ex.properties`, or
- the `TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED=true` environment variable (takes precedence over the property).

Ryuk only runs privileged when one of these is set to `true` or `1`.

## API Documentation

For more detailed information about the API, different container configurations, and advanced usage scenarios, please refer to the [API documentation](https://hexdocs.pm/testcontainer_ex/api-reference.html).

## Guides

Step-by-step guides for common tasks:

| Guide | Description |
|-------|-------------|
| [Getting Started](guides/getting_started.md) | Installation, setup, and your first container |
| [Custom Containers](guides/custom_containers.md) | Build and manage your own container configurations |
| [Container Control](guides/container_control.md) | Pause, restart, stats, file operations, and more |
| [Engine Status](guides/engine_status.md) | Query Docker/Podman/Minikube/Colima status via API |
| [Wait Strategies](guides/wait_strategies.md) | Wait for containers to be ready |
| [Connection Helpers](guides/connection_helpers.md) | Extract connection URLs and parameters |

## Windows support

### TestcontainerEx Desktop

This is the supported way to use TestcontainerEx Elixir on Windows. Download TestcontainerEx Desktop, install it and everything just works.

### Native
You can run on windows natively with elixir and erlang. But its not really supported, but I have investigated and tried it out. These are my findings:

First install Visual Studio 2022 with Desktop development with C++.

Open visual studio dev shell. I do it by just opening an empty c++ project, then View -> Terminal.

Enable "Expose daemon on tcp://localhost:2375 without TLS" in Docker settings.

for powershell:

`$Env:CONTAINER_ENGINE_HOST = "tcp://localhost:2375"`

for cmd:

`set CONTAINER_ENGINE_HOST=tcp://localhost:2375`

> **Note:** `DOCKER_HOST` is also recognized on Windows for backward compatibility.

Compile and run tests:

`mix deps.get`

`mix deps.compile`

`mix test`

## Contributing

We welcome your contributions! Please see our contributing guidelines (TBD) for more details on how to submit patches and the contribution workflow.

## License

TestcontainerEx is available under the MIT license. See the LICENSE file for more info.

## Contact

If you have any questions, issues, or want to contribute, feel free to contact us.

---

Thank you for using TestcontainerEx to test your Elixir applications!
