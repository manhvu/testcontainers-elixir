# Getting Started with TestcontainerEx

This guide walks you through setting up and using TestcontainerEx for the first time.

## Prerequisites

- **Elixir** 1.18 or later
- **Docker**, **Podman**, **Colima**, **Minikube**, or **Apple Container** installed and running
- A `Dockerfile` or container image you want to test against

## Installation

Add `testcontainer_ex` to your project's dependencies:

```elixir
# mix.exs
def deps do
  [
    {:testcontainer_ex, "~> 0.4", only: [:test, :dev]}
  ]
end
```

Then run:

```bash
mix deps.get
```

### Start the TestcontainerEx application

Add this to your `test/test_helper.exs`:

```elixir
TestcontainerEx.start_link()
```

## Quick Setup with .env

The easiest way to configure your container runtime is a `.env` file:

```bash
cp .env.example .env
```

Open `.env` and uncomment the line matching your runtime:

| Runtime | Line to uncomment |
|---------|-------------------|
| **Colima** (macOS/Linux) | `CONTAINER_ENGINE_HOST=unix://$HOME/.colima/default/docker.sock` |
| **Docker Desktop** (macOS) | `CONTAINER_ENGINE_HOST=unix://$HOME/.docker/run/docker.sock` |
| **Docker Desktop** (Windows) | `CONTAINER_ENGINE_HOST=unix://$HOME/.docker/desktop/docker.sock` |
| **Docker Engine** (Linux) | `CONTAINER_ENGINE_HOST=unix:///var/run/docker.sock` |
| **Podman** (Linux rootless) | `CONTAINER_ENGINE_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock` |
| **Minikube** | `eval $(minikube docker-env)` |
| **Apple Container** (macOS 26+, Apple silicon) | Auto-detected via `container system status` |
| **Remote Docker** (TCP) | `CONTAINER_ENGINE_HOST=tcp://192.168.1.100:2375` |

> **Note:** `DOCKER_HOST` is also recognized for backward compatibility. `CONTAINER_ENGINE_HOST` takes precedence.

## Your First Container

### Using a predefined container

TestcontainerEx ships with ready-made containers for common services:

```elixir
# Start a PostgreSQL container
{:ok, container} = TestcontainerEx.start_container(TestcontainerEx.PostgresContainer.new())

# Get connection details
opts = TestcontainerEx.Container.Info.pg_connect_opts(container)
# => [hostname: "localhost", port: 55123, username: "test", password: "test", database: "test"]

# Use it with Postgrex
{:ok, conn} = Postgrex.start_link(opts)
```

### Using a generic container

For any Docker image, use the generic container API:

```elixir
alias TestcontainerEx.Container

config = %Container.Config{image: "redis:7.2-alpine"}
|> Container.with_exposed_port(6379)

{:ok, container} = TestcontainerEx.start_container(config)

# Get the mapped port
port = TestcontainerEx.get_port(container, 6379)
# => 55123

# Connect with Redix
{:ok, conn} = Redix.start_link(host: "localhost", port: port)
```

### Using ExUnit integration

The `container` macro simplifies lifecycle management:

```elixir
defmodule MyApp.RedisTest do
  use ExUnit.Case
  import TestcontainerEx.ExUnit

  container :redis, TestcontainerEx.RedisContainer.new()

  test "stores and retrieves data", %{redis: redis} do
    conn = Redix.start_link(host: "localhost", port: TestcontainerEx.get_port(redis, 6379))
    Redix.command!(conn, ["SET", "key", "value"])
    assert Redix.command!(conn, ["GET", "key"]) == "value"
  end
end
```

The container is automatically started before each test and stopped after.

## Batch Containers

Start multiple containers at once:

```elixir
configs = [
  TestcontainerEx.PostgresContainer.new(),
  TestcontainerEx.RedisContainer.new(),
  %TestcontainerEx.Container.Config{image: "nginx:alpine"}
    |> TestcontainerEx.Container.with_exposed_port(80)
]

{:ok, containers} = TestcontainerEx.start_containers(configs)
```

If any container fails to start, `{:error, results}` is returned with per-container status.

## Container Lifecycle

```elixir
# Start
{:ok, container} = TestcontainerEx.start_container(config)

# Inspect
info = TestcontainerEx.inspect_container(container.container_id)

# Execute commands
{:ok, output} = TestcontainerEx.exec(container.container_id, ["ls", "-la", "/app"])

# Logs
{:ok, logs} = TestcontainerEx.container_logs(container.container_id, tail: 50)

# Pause / unpause
:ok = TestcontainerEx.container_pause(container.container_id)
:ok = TestcontainerEx.container_unpause(container.container_id)

# Stop
:ok = TestcontainerEx.stop_container(container.container_id)

# Remove
:ok = TestcontainerEx.container_remove(container.container_id, force: true)
```

## Next Topics

- [Custom Containers](custom_containers.md) — Build and manage your own container configurations
- [Container Control](container_control.md) — Pause, restart, stats, file operations, and more
- [Engine Status](engine_status.md) — Query Docker/Podman/Minikube/Colima/Apple Container status via API
- [Wait Strategies](wait_strategies.md) — Wait for containers to be ready
- [Connection Helpers](connection_helpers.md) — Extract connection URLs and parameters
