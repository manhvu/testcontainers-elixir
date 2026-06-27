# DevTools — Runtime Container Interaction

The `TestcontainerEx.DevTools` module provides a high-level, iex-friendly API for interacting with running containers at runtime. It's designed for developers who need to inspect, debug, and manipulate containers during development and testing.

All functions accept either a `Config.t()` struct (returned by `start_container/1`) or a raw container ID string.

## Command Execution

### Run a command inside a container

```elixir
# Execute a command and get the output as a string
{:ok, output} = TestcontainerEx.DevTools.exec(container, ["ls", "-la", "/app"])

# Execute with options
{:ok, output} = TestcontainerEx.DevTools.exec(container, ["psql", "-c", "SELECT 1"],
  user: "postgres",
  workdir: "/app",
  env: ["PGPASSWORD=secret"]
)

# Get output as a list of lines
{:ok, lines} = TestcontainerEx.DevTools.exec_lines(container, ["cat", "/etc/hosts"])
```

### Exec options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:tty` | `boolean()` | `false` | Allocate a TTY |
| `:workdir` | `String.t()` | `nil` | Working directory inside the container |
| `:user` | `String.t()` | `nil` | User (UID or name) to run as |
| `:env` | `[String.t()]` | `[]` | Environment variables (e.g. `["FOO=bar"]`) |

## File Operations

### Copy files from host to container

```elixir
# Copy a file from disk
:ok = TestcontainerEx.DevTools.copy_to(container, "/app/config.yml", "/host/path/config.yml")

# Copy a directory
:ok = TestcontainerEx.DevTools.copy_to(container, "/app/seeds", "/host/path/seeds")

# Write string contents directly
:ok = TestcontainerEx.DevTools.copy_to(container, "/tmp/data.json", ~s({"key": "value"}))
```

### Write a file (convenience wrapper)

```elixir
:ok = TestcontainerEx.DevTools.write_file(container, "/tmp/hello.txt", "world")
:ok = TestcontainerEx.DevTools.write_file(container, "/app/config.json", ~s({"debug": true}))
```

### Copy files from container to host

```elixir
# Download a file or directory to the host
:ok = TestcontainerEx.DevTools.copy_from(container, "/app/logs/server.log", "/tmp/server.log")
:ok = TestcontainerEx.DevTools.copy_from(container, "/app/data", "/tmp/container_data")
```

### Read a file from container

```elixir
# Read file contents as binary
{:ok, contents} = TestcontainerEx.DevTools.read_file(container, "/app/config.json")

# Read as a list of lines
{:ok, lines} = TestcontainerEx.DevTools.read_lines(container, "/var/log/syslog")
```

### Delete a file or directory

```elixir
:ok = TestcontainerEx.DevTools.delete_file(container, "/tmp/hello.txt")
:ok = TestcontainerEx.DevTools.delete_file(container, "/tmp/mydir")
```

### Check if a file exists

```elixir
true = TestcontainerEx.DevTools.exists?(container, "/app/config.json")
false = TestcontainerEx.DevTools.exists?(container, "/nonexistent")
```

## Directory Listing

```elixir
# List directory contents (names only)
{:ok, entries} = TestcontainerEx.DevTools.list_dir(container, "/app")
# => {:ok, ["config.json", "lib", "mix.exs"]}

# List with details (permissions, size, etc.)
{:ok, entries} = TestcontainerEx.DevTools.list_dir_long(container, "/app")
# => {:ok, ["drwxr-xr-x 2 root Root 4096 Jan 1 00: 00 lib", ...]}
```

## Process Management

### Kill a process by PID

```elixir
:ok = TestcontainerEx.DevTools.kill_process(container, 123)
:ok = TestcontainerEx.DevTools.kill_process(container, 456, signal: "SIGTERM")
```

### Kill processes by name

```elixir
:ok = TestcontainerEx.DevTools.kill_process_name(container, "nginx")
:ok = TestcontainerEx.DevTools.kill_process_name(container, "my_app", signal: "SIGTERM", exact: true)
```

### Find PIDs by process name

```elixir
{:ok, pids} = TestcontainerEx.DevTools.find_pids(container, "nginx")
# => {:ok, [123, 456]}
```

### List running processes

```elixir
{:ok, top} = TestcontainerEx.DevTools.processes(container)
# => {:ok, %{"Titles" => ["UID", "PID", "CMD"], "Processes" => [...]}}

# Custom ps arguments
{:ok, top} = TestcontainerEx.DevTools.processes(container, ps_args: "aux")
```

## Container Info

### Get container state

```elixir
{:ok, state} = TestcontainerEx.DevTools.state(container)
# => {:ok, %{"Running" => true, "Paused" => false, ...}}
```

### Check if running

```elixir
true = TestcontainerEx.DevTools.running?(container)
```

### Get resource usage stats

```elixir
{:ok, stats} = TestcontainerEx.DevTools.stats(container)
# => {:ok, %{"cpu_stats" => ..., "memory_stats" => ..., "networks" => ...}}
```

## Using the public API

All DevTools functions are also available through the main `TestcontainerEx` module with the `dev_` prefix:

```elixir
TestcontainerEx.dev_exec(container, ["ls", "/app"])
TestcontainerEx.dev_write_file(container, "/tmp/test.txt", "hello")
TestcontainerEx.dev_read_file(container, "/tmp/test.txt")
TestcontainerEx.dev_delete_file(container, "/tmp/test.txt")
TestcontainerEx.dev_kill_process(container, 123)
TestcontainerEx.dev_kill_process_name(container, "nginx")
TestcontainerEx.dev_find_pids(container, "nginx")
TestcontainerEx.dev_list_dir(container, "/app")
TestcontainerEx.dev_copy_to(container, "/app/file.txt", "local_file.txt")
TestcontainerEx.dev_copy_from(container, "/app/logs", "/tmp/logs")
```

## Complete API Reference

| Function | Description | Returns |
|----------|-------------|---------|
| `exec/3` | Run a command | `{:ok, output}` \| `{:error, reason}` |
| `exec_lines/3` | Run a command, get lines | `{:ok, [String.t()]}` \| `{:error, reason}` |
| `copy_to/4` | Copy host → container | `:ok` \| `{:error, reason}` |
| `write_file/4` | Write string to file in container | `:ok` \| `{:error, reason}` |
| `copy_from/4` | Copy container → host | `:ok` \| `{:error, reason}` |
| `read_file/3` | Read file from container | `{:ok, binary()}` \| `{:error, reason}` |
| `read_lines/3` | Read file as lines | `{:ok, [String.t()]}` \| `{:error, reason}` |
| `delete_file/3` | Delete file/directory | `:ok` \| `{:error, reason}` |
| `exists?/3` | Check if path exists | `boolean()` |
| `list_dir/3` | List directory entries | `{:ok, [String.t()]}` \| `{:error, reason}` |
| `list_dir_long/3` | List with details | `{:ok, [String.t()]}` \| `{:error, reason}` |
| `kill_process/3` | Kill process by PID | `:ok` \| `{:error, reason}` |
| `kill_process_name/3` | Kill processes by name | `:ok` |
| `find_pids/3` | Find PIDs by name | `{:ok, [integer()]}` \| `{:error, reason}` |
| `processes/2` | List running processes | `{:ok, map()}` \| `{:error, reason}` |
| `stats/2` | Get resource usage | `{:ok, map()}` \| `{:error, reason}` |
| `state/2` | Get container state | `{:ok, map()}` \| `{:error, reason}` |
| `running?/2` | Check if running | `boolean()` |
