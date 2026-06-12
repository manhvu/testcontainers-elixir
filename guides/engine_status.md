# Engine Status

The `TestcontainerEx.Docker.Status` module lets you query the runtime status of container engines (Docker, Podman, Minikube, Colima) directly via their APIs or CLI. These functions don't require the TestcontainerEx GenServer — they work standalone.

## Quick Checks

```elixir
# Is any container engine reachable?
TestcontainerEx.engine_reachable?()
# => true

# Ping the Docker Engine API
TestcontainerEx.engine_ping()
# => :ok
```

## Normalized Engine Status

Get a consistent status map for any supported engine:

```elixir
# Auto-detect and query
status = TestcontainerEx.engine_status()
# %{
#   engine: :docker,
#   running: true,
#   version: "27.0.3",
#   api_version: "1.43",
#   os: "Docker Desktop",
#   arch: "aarch64",
#   cpus: 8,
#   memory_bytes: 8_589_934_592,
#   hostname: "docker-desktop",
#   kernel_version: "6.10.14-linuxkit",
#   storage_driver: "overlay2",
#   logging_driver: "json-file",
#   cgroup_driver: "cgroupfs",
#   cgroup_version: "1",
#   plugins: ["Volume: local", "Network: bridge", ...],
#   registries: ["docker.io", "ghcr.io"],
#   server_time: ~U[2026-06-12 10:00:00Z],
#   labels: %{"os" => "linux"},
#   experimental: false,
#   raw: %{...}  # full API response
# }

# Query a specific engine
TestcontainerEx.engine_status(:podman)
TestcontainerEx.engine_status(:colima)
TestcontainerEx.engine_status(:minikube)
```

## Colima Status

```elixir
status = TestcontainerEx.colima_status()
# %{
#   running: true,
#   profile: "default",
#   colima_version: "0.6.8",
#   socket_path: "/Users/you/.colima/default/docker.sock",
#   kubernetes: false,
#   cpu: 4,
#   memory_bytes: 4_294_967_296,
#   disk_bytes: 107_374_182_400,
#   arch: "aarch64",
#   runtime: "docker",
#   network_address: "192.168.5.2",
#   raw: %{...}
# }
```

## Minikube Status

```elixir
status = TestcontainerEx.minikube_status()
# %{
#   running: true,
#   profile: "minikube",
#   minikube_version: "1.33.1",
#   cpus: 4,
#   memory_mb: 4096,
#   disk_mb: 20000,
#   driver: "docker",
#   container_runtime: "docker",
#   kubernetes_version: "v1.30.0",
#   apiserver: true,
#   raw: %{...}
# }
```

## Docker Engine API Queries

```elixir
# Full daemon info
{:ok, info} = TestcontainerEx.engine_info()
IO.puts(info["ServerVersion"])   # "27.0.3"
IO.puts(info["NCPU"])            # 8
IO.puts(info["Driver"])          # "overlay2"

# Version details
{:ok, version} = TestcontainerEx.engine_version()
IO.puts(version["Version"])      # "27.0.3"
IO.puts(version["ApiVersion"])   # "1.43"

# List all containers (including stopped)
{:ok, containers} = TestcontainerEx.list_containers(all: true)

# List with filters
{:ok, containers} = TestcontainerEx.list_containers(
  filters: %{"label" => ["env=test"], "status" => ["running"]}
)

# List images
{:ok, images} = TestcontainerEx.list_images()

# List networks
{:ok, networks} = TestcontainerEx.list_networks()

# List volumes
{:ok, volumes} = TestcontainerEx.list_volumes()

# Disk usage summary
{:ok, df} = TestcontainerEx.disk_usage()
# %{
#   "LayersSize" => 1234567890,
#   "Images" => [...],
#   "Containers" => [...],
#   "Volumes" => [...]
# }
```

## Event Stream

```elixir
# Stream Docker events in real-time
{:ok, stream} = TestcontainerEx.engine_events()

# Filtered events
{:ok, stream} = TestcontainerEx.engine_events(
  filters: %{"type" => ["container"], "event" => ["start", "stop", "die"]}
)

# Events since a timestamp
{:ok, stream} = TestcontainerEx.engine_events(since: 1_700_000_000)
```

## Direct Module Access

For more control, use the module directly:

```elixir
alias TestcontainerEx.Docker.Status

# Check reachability
Status.reachable?()

# Query specific engine
Status.status(:docker)
Status.status(:colima)

# Colima-specific details
Status.colima_status()

# Minikube-specific details
Status.minikube_status()

# Raw Docker Engine API
Status.engine_info("http://remote-docker:2375")
Status.engine_version()
Status.list_containers(all: true, limit: 10)
Status.list_images()
Status.list_networks()
Status.list_volumes()
Status.disk_usage()
Status.ping()
Status.events(filters: %{"type" => ["container"]})
```

## Health Check Pattern

Use engine status for application health checks:

```elixir
defmodule MyApp.Health do
  def check do
    with %{running: true} <- TestcontainerEx.engine_status(),
         :ok <- TestcontainerEx.engine_ping() do
      :ok
    else
      %{running: false} -> {:error, :engine_not_running}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Multi-Engine Detection

```elixir
# Check which engines are available
engines = [
  docker: TestcontainerEx.engine_status(:docker),
  podman: TestcontainerEx.engine_status(:podman),
  colima: TestcontainerEx.engine_status(:colima),
  minikube: TestcontainerEx.engine_status(:minikube)
]

running = for {name, %{running: true}} <- engines, do: name
IO.puts("Running engines: #{Enum.join(running, ", ")}")
```
