# TestcontainerEx

[![Hex.pm](https://img.shields.io/hexpm/v/testcontainer_ex.svg)](https://hex.pm/packages/testcontainer_ex)

> Forked from [testcontainers-elixir](https://github.com/testcontainers/testcontainers-elixir), with added support for Podman, Minikube, and Colima, a `.env` file for project-local Docker host configuration, and a clean architecture refactor.

> TestcontainerEx is an Elixir library that supports ExUnit tests, providing lightweight, throwaway instances of common databases, Selenium web browsers, or anything else that can run in a Docker or Podman container.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Podman Support](#podman-support)
- [Minikube Support](#minikube-support)
- [Colima Support](#colima-support)
- [Docker Host Resolution](#docker-host-resolution)
- [Configuration](#configuration)
- [API Documentation](#api-documentation)
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
    {:testcontainer_ex, "~> X.XX", only: [:test, :dev]}
  ]
end
```

Replace X.XX with the current major and minor version.

2. Run mix deps.get

3. Add the following to test/test_helper.exs

```elixir
TestcontainerEx.start_link()
```

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

#### Backward Compatibility

For backward compatibility, the old `mix testcontainer_ex.test` task is still available and works exactly as before. It automatically delegates to `mix testcontainer_ex.run test`, so existing scripts and workflows will continue to work without modification:

```bash
# These commands are equivalent:
mix testcontainer_ex.test --database mysql
mix testcontainer_ex.run test --database mysql

# Both support all the same options:
mix testcontainer_ex.test --database postgres --db-volume my_data
mix testcontainer_ex.run test --database postgres --db-volume my_data
```

While the old task will continue to work, we recommend updating to `mix testcontainer_ex.run` for new projects as it provides more flexibility by allowing you to run any Mix task, not just tests.

### Logging

TestcontainerEx use the standard Logger, see https://hexdocs.pm/logger/Logger.html.

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

Podman uses `CONTAINER_HOST` instead of `DOCKER_HOST`:

| Variable | Description |
|----------|-------------|
| `CONTAINER_HOST` | Podman socket path, e.g. `unix:///run/user/1000/podman/podman.sock` |
| `DOCKER_HOST` | Also supported for compatibility |

Both `DOCKER_HOST` and `CONTAINER_HOST` are recognized. `DOCKER_HOST` is checked first, then `CONTAINER_HOST`.

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

- `$XDG_RUNTIME_DIR/podman/podman.sock` (rootless Podman)
- `$XDG_RUNTIME_DIR/containers/podman.sock`
- `$XDG_RUNTIME_DIR/docker.sock`
- `/var/run/docker.sock` (rootful Podman with Docker compatibility)
- `~/.colima/default/docker.sock` (Colima with Podman runtime)

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

   The `minikube docker-env` command sets `DOCKER_HOST`, `DOCKER_CERT_PATH`, and
   `DOCKER_TLS_VERIFY` environment variables. TestcontainerEx reads all of these
   automatically.

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
- A `DOCKER_HOST` value in the `192.168.49.0/24` subnet (minikube's default)
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

   TestcontainerEx automatically detects the Colima socket at `~/.colima/default/docker.sock`.

### Specifying the Colima socket explicitly

If auto-detection does not work (e.g. you use a named Colima profile), you can set the socket path via any of the standard configuration methods:

```bash
# Environment variable
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock

# Or in ~/.testcontainer_ex.properties
echo "tc.host=unix://$HOME/.colima/default/docker.sock" >> ~/.testcontainer_ex.properties

# Or in a project .env file
echo "DOCKER_HOST=unix://$HOME/.colima/default/docker.sock" >> .env
```

### Detected Socket Path

The library automatically detects the Colima socket at:

- `~/.colima/default/docker.sock` (default profile)

For named profiles, the socket is at `~/.colima/<profile>/docker.sock` — set `DOCKER_HOST` explicitly for these.

See [Docker Host Resolution](#docker-host-resolution) for the full list of detected socket paths.

## Docker Host Resolution

TestcontainerEx resolves the container engine host by trying several strategies in order. The first strategy that succeeds wins.

### Resolution order

| Priority | Strategy | Source | Notes |
|----------|----------|--------|-------|
| 1 | **Properties file** | `~/.testcontainer_ex.properties` | Checks `tc.host`, then `docker.host` |
| 2 | **Environment variable** | `DOCKER_HOST` | Standard Docker env var (shell/profile) |
| 3 | **`.env` file** | `.env` in project root | Project-local default; only used when `DOCKER_HOST` is unset |
| 4 | **Container env var** | `CONTAINER_HOST` | Podman equivalent of `DOCKER_HOST` |
| 5 | **Minikube** | `minikube docker-env` | Auto-detected when minikube is available |
| 6 | **Socket scan** | Well-known paths | Docker Desktop, Docker Engine, Podman, Colima sockets |

### `.env` file

You can place a `.env` file in your project root to configure the Docker host without modifying your shell profile:

```bash
# .env
DOCKER_HOST=unix:///Users/you/.colima/default/docker.sock
```

This is especially useful for Colima users on macOS, where the socket path is not in the default search list and `DOCKER_HOST` is not automatically exported.

The `.env` file uses simple `KEY=VALUE` syntax, one per line. Lines starting with `#` are comments:

```bash
# .env — project-local Docker host config
DOCKER_HOST=unix:///Users/you/.colima/default/docker.sock
```

> **Note:** The `.env` file is only consulted when `DOCKER_HOST` is not already set in your environment. Shell/profile settings always take precedence.

### Socket auto-detection

When no explicit host is configured, TestcontainerEx scans these socket paths:

| Path | Runtime |
|------|---------|
| `/var/run/docker.sock` | Docker Engine (Linux) |
| `~/.docker/run/docker.sock` | Docker Desktop (macOS/Windows) |
| `~/.docker/desktop/docker.sock` | Docker Desktop (alternate) |
| `~/.colima/default/docker.sock` | Colima (default profile) |
| `$XDG_RUNTIME_DIR/podman/podman.sock` | Podman (rootless) |
| `$XDG_RUNTIME_DIR/containers/podman.sock` | Podman (alternate) |
| `$XDG_RUNTIME_DIR/docker.sock` | Generic XDG socket |
| `/var/run/minikube/docker.sock` | Minikube |

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

If the image lives on a registry that requires authentication, TestcontainerEx automatically resolves credentials from the user's Docker config on image pull. The lookup order is:

1. `Container.auth` if set explicitly — always wins.
2. The `auths` map in `$DOCKER_CONFIG/config.json` (or `~/.docker/config.json` if `DOCKER_CONFIG` is unset). The registry host of the image is matched against entries in the map.
3. Anonymous pull.

Only the `auths` map is consulted; credential-helper binaries (`credsStore`, `credHelpers`) are not invoked. If an auto-resolved credential is rejected with a 4xx, the pull is retried once anonymously to keep stale entries in `config.json` from breaking pulls that would otherwise succeed without auth.

To log in before running tests:

```bash
docker login myregistry.example.com
```

### TLS-secured Docker hosts

TestcontainerEx recognizes TLS-secured Docker daemons out of the box. Point it at one with:

- `DOCKER_HOST=https://docker.example.internal:2376`, or
- `DOCKER_HOST=tcp://docker.example.internal:2376` plus `DOCKER_TLS_VERIFY=1`.

The client looks for `ca.pem`, `cert.pem`, and `key.pem` in the directory named by `DOCKER_CERT_PATH` (or `~/.docker` if unset); whichever files are present are used to build the SSL context, matching the Docker CLI's behavior. When `DOCKER_TLS_VERIFY` is unset, peer verification is disabled and a warning is logged.

### Ryuk under SELinux / rootless Docker or Podman

On distributions that enforce SELinux (for example Fedora), the Ryuk reaper container may be denied write access to the Docker/Podman socket unless it runs privileged. This is especially common with rootless Podman. Enable it with either:

- the `ryuk.container.privileged=true` property in `~/.testcontainer_ex.properties`, or
- the `TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED=true` environment variable (takes precedence over the property).

Ryuk only runs privileged when one of these is set to `true` or `1`.

## API Documentation

For more detailed information about the API, different container configurations, and advanced usage scenarios, please refer to the [API documentation](https://hexdocs.pm/testcontainer_ex/api-reference.html).

## Windows support

### TestcontainerEx Desktop

This is the supported way to use TestcontainerEx Elixir on Windows. Download TestcontainerEx Desktop, install it and everything just works.

### Native
You can run on windows natively with elixir and erlang. But its not really supported, but I have investigated and tried it out. These are my findings:

First install Visual Studio 2022 with Desktop development with C++.

Open visual studio dev shell. I do it by just opening an empty c++ project, then View -> Terminal.

Enable "Expose daemon on tcp://localhost:2375 without TLS" in Docker settings.

for powershell:

`$Env:DOCKER_HOST = "tcp://localhost:2375"`

for cmd:

`set DOCKER_HOST=tcp://localhost:2375`

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
