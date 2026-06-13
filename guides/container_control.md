# Container Control

The `TestcontainerEx.Engine.Control` module provides low-level container operations via the Docker Engine API (or equivalent CLI for Apple Container). These functions work with raw container IDs and don't require the TestcontainerEx GenServer — they create their own HTTP clients.

All functions accept an optional `base_url` parameter. When omitted, it's derived from `CONTAINER_ENGINE_HOST` (or `DOCKER_HOST` as fallback), or defaults to `http://d`.

## Lifecycle Operations

```elixir
alias TestcontainerEx.Engine.Control

# Start a stopped container
:ok = Control.start("abc123")

# Stop (with optional timeout in seconds)
:ok = Control.stop("abc123", 30)

# Restart
:ok = Control.restart("abc123", 10)

# Kill with a signal
:ok = Control.kill("abc123", "SIGTERM")

# Pause and unpause
:ok = Control.pause("abc123")
:ok = Control.unpause("abc123")

# Remove (with options)
:ok = Control.remove("abc123", force: true, remove_volumes: true)

# Rename
:ok = Control.rename("abc123", "my-new-name")

# Wait for container to exit
{:ok, exit_code} = Control.wait("abc123")
```

## Container Creation

```elixir
# Create from a config map
{:ok, id} = Control.create(%{
  "Image" => "nginx:alpine",
  "ExposedPorts" => %{"80/tcp" => %{}},
  "HostConfig" => %{
    "PortBindings" => %{"80/tcp" => [%{"HostPort" => "8080"}]}
  }
})

# Create with a name
{:ok, id} = Control.create("my-nginx", %{
  "Image" => "nginx:alpine",
  "ExposedPorts" => %{"80/tcp" => %{}}
})
```

## Inspection

```elixir
# Full inspection
{:ok, info} = Control.inspect("abc123")
# %{"Id" => "...", "State" => %{"Running" => true, ...}, "NetworkSettings" => ...}

# Just the state
{:ok, state} = Control.state("abc123")
# %{"Running" => true, "Paused" => false, "ExitCode" => 0, ...}

# Quick boolean check
true = Control.running?("abc123")
```

## Resource Updates

```elixir
# Update memory, CPU, and other resources
:ok = Control.update("abc123",
  memory: 536_870_912,           # 512 MB
  memory_swap: 1_073_741_824,    # 1 GB
  nano_cpus: 500_000_000,        # 0.5 CPU
  cpu_shares: 512,
  pids_limit: 100,
  restart_policy: "on-failure:5"
)
```

## Logs

```elixir
# Get all logs
{:ok, logs} = Control.logs("abc123")

# Tail last 100 lines
{:ok, logs} = Control.logs("abc123", tail: 100)

# Only stdout with timestamps
{:ok, logs} = Control.logs("abc123",
  stdout: true,
  stderr: false,
  timestamps: true
)

# Logs since a UNIX timestamp
{:ok, logs} = Control.logs("abc123", since: 1_700_000_000)
```

## Exec

```elixir
# Create an exec instance
{:ok, exec_id} = Control.create_exec("abc123", ["ps", "aux"])

# Create with options
{:ok, exec_id} = Control.create_exec("abc123", ["bash"],
  tty: true,
  attach_stdin: true,
  attach_stdout: true,
  env: ["TERM=xterm"],
  workdir: "/app",
  user: "root"
)

# Start the exec
{:ok, output} = Control.start_exec(exec_id, tty: true)

# Inspect exec status
{:ok, status} = Control.inspect_exec(exec_id)
# %{"Running" => false, "ExitCode" => 0}

# Resize TTY
:ok = Control.resize_exec(exec_id, 80, 24)
```

## Stats & Processes

```elixir
# Get resource usage stats (one-shot)
{:ok, stats} = Control.stats("abc123", stream: false)
# %{
#   "cpu_stats" => %{"cpu_usage" => %{"total_usage" => ...}},
#   "memory_stats" => %{"usage" => ..., "limit" => ...},
#   "networks" => %{"eth0" => %{"rx_bytes" => ..., "tx_bytes" => ...}}
# }

# Get running processes
{:ok, top} = Control.top("abc123")
# %{"Titles" => ["UID", "PID", "CMD"], "Processes" => [...]}

# Custom ps args
{:ok, top} = Control.top("abc123", "aux")
```

## File Operations

```elixir
# Upload a file from disk
:ok = Control.upload("abc123", "/app/config.yml", "/host/path/config.yml")

# Upload binary contents
:ok = Control.upload("abc123", "/app/data.json", "{\"key\": \"value\"}")

# Download a file (returns raw tar archive)
{:ok, tar_data} = Control.download("abc123", "/app/data/output.json")

# Download and extract a single file
{:ok, contents} = Control.download_file("abc123", "/app/data/output.json")
```

## Image Operations

```elixir
# Commit container to a new image
{:ok, image_id} = Control.commit("abc123", "my-snapshot:v1")

# Commit with options
{:ok, image_id} = Control.commit("abc123", "my-snapshot:v1",
  pause: true,
  comment: "Snapshot after migration",
  author: "Test Suite"
)

# Export container filesystem
{:ok, tarball} = Control.export("abc123")
```

## TTY & Attach

```elixir
# Resize container TTY
:ok = Control.resize("abc123", 80, 24)

# Attach to container streams
{:ok, stream_ref} = Control.attach("abc123",
  stream: true,
  stdout: true,
  stderr: true,
  logs: true
)
```

## Using with CustomContainer

The control functions work with any container started via TestcontainerEx:

```elixir
alias TestcontainerEx.CustomContainer

config =
  CustomContainer.new("my-app:latest")
  |> CustomContainer.with_exposed_port(8080)

{:ok, container} = TestcontainerEx.start_container(config)
id = container.container_id

# Use low-level control
:ok = TestcontainerEx.container_pause(id)
:ok = TestcontainerEx.container_unpause(id)

stats = TestcontainerEx.container_stats(id)
IO.puts("Memory usage: #{stats["memory_stats"]["usage"]}")

:ok = TestcontainerEx.stop_container(id)
:ok = TestcontainerEx.container_remove(id, force: true)
```

## Direct API Access (No GenServer)

All control functions can be called without starting the GenServer — just pass a `base_url`:

```elixir
# Connect to a remote Docker host
base_url = "http://192.168.1.100:2375"

{:ok, info} = TestcontainerEx.Engine.Control.inspect("abc123", base_url)
:ok = TestcontainerEx.Engine.Control.pause("abc123", base_url)

# Connect via unix socket
base_url = "unix:///var/run/docker.sock"
{:ok, stats} = TestcontainerEx.Engine.Control.stats("abc123", base_url)
```
