# Runtime Engine Selection

TestcontainerEx supports selecting the container engine at runtime through three
mechanisms, listed in order of precedence:

| Priority | Mechanism | Scope |
|----------|-----------|-------|
| 1 (highest) | `set_engine/1` | Per-process |
| 2 | `start_link(engine: :docker)` | Per-server |
| 3 | `CONTAINER_ENGINE` env var | Global |

## Quick Start

```elixir
# Override to Podman for the current process
TestcontainerEx.set_engine(:podman)
TestcontainerEx.container_engine() # => :podman

# Start a server with an explicit engine
TestcontainerEx.start_link(engine: :colima)

# Switch a running server to a different engine
TestcontainerEx.reconnect(engine: :docker)
```

## The Three Selection Methods

### 1. Runtime Override — `set_engine/1`

Stores the engine choice in the calling process's dictionary. This takes
precedence over everything else and is ideal for tests that need to target a
specific engine without changing global state.

```elixir
# In a test file
setup do
  TestcontainerEx.set_engine(:podman)
  on_exit(&TestcontainerEx.clear_engine/0)
  :ok
end

test "something with Podman" do
  # All TestcontainerEx calls in this process use Podman
  assert TestcontainerEx.container_engine() == :podman
end
```

Key properties:
- **Per-process**: other processes are unaffected
- **Auto-cleaned**: disappears when the calling process exits
- **Highest precedence**: overrides `CONTAINER_ENGINE` env var and auto-detection

To reset:

```elixir
TestcontainerEx.clear_engine()
```

### 2. Server Option — `start_link/1`

Pass the `:engine` option when starting the GenServer. This is stored in the
server's state and used for connection resolution.

```elixir
TestcontainerEx.start_link(engine: :minikube)
TestcontainerEx.get_engine() # => :minikube
```

This is useful when your application configures the engine at startup (e.g.,
from `runtime.exs` or application env).

### 3. Environment Variable — `CONTAINER_ENGINE`

Set `CONTAINER_ENGINE` to one of `auto`, `docker`, `podman`, `colima`,
`minikube`, or `apple_container`:

```bash
CONTAINER_ENGINE=podman mix test
```

This is the simplest way to select an engine for an entire test run or
deployment. It is read at resolution time, so it works even if the env var
is set after the application starts.

## Runtime Reconnection

`reconnect/1` switches a running server to a different engine:

```elixir
# Start with Docker
{:ok, _} = TestcontainerEx.start_link(engine: :docker)

# Later, switch to Podman
{:ok, :podman} = TestcontainerEx.reconnect(engine: :podman)
```

**Warning**: `reconnect/1` stops all tracked containers, networks, and compose
environments before re-initializing. Use it between test phases, not in the
middle of a test that depends on running containers.

## Inspecting the Current Engine

```elixir
# What engine is the server configured with?
TestcontainerEx.get_engine()        # => :auto | :docker | :podman | ...

# What engine is actually detected/resolved?
TestcontainerEx.container_engine()  # => :docker | :podman | :minikube | ...

# Is there a runtime override in the current process?
TestcontainerEx.Engine.runtime_override()  # => nil | :docker | :podman | ...
```

- `get_engine/1` returns the engine **configured** on the server (`:auto` if
  no explicit engine was set).
- `container_engine/0` returns the **resolved** engine (never `:auto`).
- `Engine.runtime_override/0` returns the process-level override, if any.

## Supported Engines

| Engine | Strategies Tried |
|--------|-----------------|
| `:auto` | All strategies in priority order |
| `:docker` | Socket, Colima, ContainerEnv |
| `:podman` | Socket, ContainerEnv |
| `:colima` | Colima only |
| `:minikube` | Minikube only |
| `:apple_container` | Apple Container only |

## Example: Multi-Engine Test Suite

```elixir
defmodule MultiEngineTest do
  use ExUnit.Case, async: false

  @engines [:docker, :podman]

  for engine <- @engines do
    @engine engine
    test "works with #{@engine}" do
      # Skip if the engine is not available
      case TestcontainerEx.Engine.Status.status(@engine) do
        %{running: true} -> :ok
        _ -> flunk("#{@engine} is not running")
      end

      TestcontainerEx.set_engine(@engine)

      config = TestcontainerEx.Container.new("nginx:alpine")
      {:ok, container} = TestcontainerEx.start_container(config)

      assert TestcontainerEx.container_engine() == @engine

      TestcontainerEx.stop_container(container.container_id)
    end
  end
end
```

## Example: Application Configuration

In `config/runtime.exs`:

```elixir
config :my_app, :testcontainer_engine,
  System.get_env("CONTAINER_ENGINE", "auto")
```

In `test/test_helper.exs`:

```elixir
engine = Application.fetch_env!(:my_app, :testcontainer_engine)
TestcontainerEx.set_engine(String.to_existing_atom(engine))
```

## Run Script Integration

The `script/run_docker_tests.sh` script respects `CONTAINER_ENGINE` to start only
the selected engine:

```bash
# Start Docker Desktop only (not Colima)
CONTAINER_ENGINE=docker script/run_docker_tests.sh

# Start Podman machine only
CONTAINER_ENGINE=podman script/run_docker_tests.sh

# Start Minikube only
CONTAINER_ENGINE=minikube script/run_docker_tests.sh

# Auto mode (default): starts Colima if available
script/run_docker_tests.sh
```

When `CONTAINER_ENGINE` is set to a specific engine, the script skips the
default Colima startup and only starts/checks the requested engine. This avoids
unnecessarily running multiple container engines simultaneously.

## Test Helper Integration

`test/test_helper.exs` also respects `CONTAINER_ENGINE`. When the env var is set:

- `"colima"` — starts/restarts Colima (existing behavior)
- `"docker"` — checks Docker daemon is running (does NOT start Colima)
- `"podman"` — starts Podman machine if not running
- `"minikube"` — starts Minikube if not running
- `"apple_container"` — starts Apple Container if not running
- `"auto"` or unset — falls back to Colima-first behavior

This means you can run the full test suite against a specific engine:

```bash
CONTAINER_ENGINE=docker mix test --include needs_dock
```

## Caching Behavior

`Engine.detect()` caches the result in `:persistent_term` after the first call.
This means:

- Within the same BEAM process, repeated calls return the cached value
- Changing `CONTAINER_ENGINE` env var mid-process has no effect until cache is cleared
- Call `TestcontainerEx.Engine.clear_engine()` to reset the cache

The `CONTAINER_ENGINE` env var is read at first `detect()` call, not at compile time.
Each new BEAM process (e.g., `mix test` invocation) re-reads the env var.
