# Custom Containers

`TestcontainerEx.CustomContainer` lets you define any container configuration with a fluent builder API, then start and manage it through the standard TestcontainerEx API.

## Basic Usage

```elixir
alias TestcontainerEx.CustomContainer

config =
  CustomContainer.new("my-app:latest")
  |> CustomContainer.with_exposed_port(8080)
  |> CustomContainer.with_env("DATABASE_URL", "postgres://localhost/mydb")
  |> CustomContainer.with_name("my-app")

{:ok, container} = TestcontainerEx.start_container(config)
```

`CustomContainer` implements the `Builder` protocol, so it works anywhere a builder is accepted — `start_container/1`, `start_containers/1`, and the ExUnit `container` macro.

## Builder Reference

### Image & Command

```elixir
CustomContainer.new("nginx:1.25")
|> CustomContainer.with_image("nginx:1.26")          # override image
|> CustomContainer.with_cmd(["nginx", "-g", "daemon off;"])
|> CustomContainer.with_entrypoint(["/entrypoint.sh"])
|> CustomContainer.with_workdir("/app")
```

### Ports

```elixir
|> CustomContainer.with_exposed_port(80)              # random host port
|> CustomContainer.with_exposed_ports([80, 443])      # multiple random ports
|> CustomContainer.with_fixed_port(80, 8080)          # container 80 -> host 8080
```

### Environment

```elixir
|> CustomContainer.with_env("RACK_ENV", "production")
|> CustomContainer.with_envs(%{
  "DB_HOST" => "localhost",
  "DB_PORT" => "5432",
  "DB_NAME" => "myapp_test"
})
```

### Volumes & Files

```elixir
# Bind mount (host path -> container path)
|> CustomContainer.with_volume("/host/data", "/app/data", "rw")

# Named volume
|> CustomContainer.with_named_volume("my-vol", "/app/data", read_only: false)

# Copy file contents at startup
|> CustomContainer.with_copy_file("/app/config.yml", "key: value\n")
```

### Networking

```elixir
|> CustomContainer.with_network("my-network")
|> CustomContainer.with_network_mode("host")          # host networking
|> CustomContainer.with_hostname("my-app")
|> CustomContainer.with_dns(["8.8.8.8", "8.8.4.4"])
|> CustomContainer.with_extra_host("database", "10.0.0.5")
```

### Identity & Labels

```elixir
|> CustomContainer.with_name("my-app")
|> CustomContainer.with_label("env", "test")
|> CustomContainer.with_labels(%{
  "app" => "my-app",
  "version" => "1.0"
})
```

### Resources

```elixir
|> CustomContainer.with_privileged(true)
|> CustomContainer.with_user("1000:1000")
|> CustomContainer.with_memory_limit(536_870_912)     # 512 MB
|> CustomContainer.with_cpu_limit(0.5)                 # half a CPU core
|> CustomContainer.with_restart_policy("unless-stopped")
|> CustomContainer.with_stop_timeout(30)               # 30 seconds
```

### Wait Strategies

```elixir
import TestcontainerEx.Wait

|> CustomContainer.with_wait_strategy(
  http("/health", 8080, status_code: 200)
)
|> CustomContainer.with_wait_strategies([
  log(~r/Server started/, 30_000),
  port("localhost", 8080, 30_000)
])
```

### Post-Start Callback

```elixir
|> CustomContainer.after_start(fn _cc, container, conn ->
  # Run migrations, seed data, etc.
  TestcontainerEx.exec(container.container_id, ["mix", "ecto.migrate"])
end)
```

## Runtime Info

After starting a container, extract connection details:

```elixir
{:ok, container} = TestcontainerEx.start_container(config)

# Runtime info map
info = CustomContainer.runtime_info(container)
# %{
#   container_id: "abc123...",
#   image: "my-app:latest",
#   name: "my-app",
#   ip_address: "172.17.0.3",
#   ports: [{8080, 55123}],
#   environment: %{"DATABASE_URL" => "..."},
#   ...
# }

# Get host:port for a container port
{host, port} = CustomContainer.endpoint(container, 8080)
# => {"localhost", 55123}

# Get a connection URL
url = CustomContainer.endpoint_url(container, 5432, "postgres")
# => "postgres://localhost:55124"

# With authentication
url = CustomContainer.endpoint_url(container, 5432, "postgres",
  username: "admin", password: "secret"
)
# => "postgres://admin:secret@localhost:55124"
```

## ExUnit Integration

```elixir
defmodule MyApp.IntegrationTest do
  use ExUnit.Case
  import TestcontainerEx.ExUnit

  container :my_app,
    CustomContainer.new("my-app:latest")
    |> CustomContainer.with_exposed_port(8080)
    |> CustomContainer.with_wait_strategy(
      TestcontainerEx.Wait.http("/health", 8080)
    )

  test "application responds", %{my_app: container} do
    port = TestcontainerEx.get_port(container, 8080)
    {:ok, %{status: 200}} = Tesla.get("http://localhost:#{port}/health")
  end
end
```

## Shared Container Across Tests

Use `shared: true` to start the container once for the entire module:

```elixir
defmodule MyApp.SharedTest do
  use ExUnit.Case
  import TestcontainerEx.ExUnit

  container :db,
    CustomContainer.new("postgres:15-alpine")
    |> CustomContainer.with_exposed_port(5432)
    |> CustomContainer.with_env("POSTGRES_PASSWORD", "test")
    |> CustomContainer.with_wait_strategy(
      TestcontainerEx.Wait.command(["pg_isready", "-U", "postgres"], 30_000)
    ),
    shared: true

  test "connection works", %{db: db} do
    opts = TestcontainerEx.Container.Info.pg_connect_opts(db)
    {:ok, conn} = Postgrex.start_link(opts)
    assert Postgrex.query!(conn, "SELECT 1", []) != nil
  end
end
```

## From an Existing Config

If you already have a `Container.Config`, wrap it:

```elixir
config = %TestcontainerEx.Container.Config{image: "nginx:alpine"}
|> TestcontainerEx.Container.with_exposed_port(80)

cc = CustomContainer.from_config(config)
{:ok, container} = TestcontainerEx.start_container(cc)
```

## Complete Example

```elixir
defmodule MyApp.DatabaseTest do
  use ExUnit.Case
  import TestcontainerEx.ExUnit

  container :postgres,
    CustomContainer.new("postgres:15-alpine")
    |> CustomContainer.with_name("test-postgres")
    |> CustomContainer.with_exposed_port(5432)
    |> CustomContainer.with_env("POSTGRES_USER", "test")
    |> CustomContainer.with_env("POSTGRES_PASSWORD", "test")
    |> CustomContainer.with_env("POSTGRES_DB", "myapp_test")
    |> CustomContainer.with_volume("pgdata", "/var/lib/postgresql/data")
    |> CustomContainer.with_wait_strategy(
      TestcontainerEx.Wait.command(
        ["pg_isready", "-U", "test", "-d", "myapp_test"],
        60_000
      )
    )
    |> CustomContainer.with_restart_policy("unless-stopped")
    |> CustomContainer.with_stop_timeout(10)
    |> CustomContainer.after_start(fn _cc, container, _conn ->
      opts = TestcontainerEx.Container.Info.pg_connect_opts(container)
      {:ok, conn} = Postgrex.start_link(opts)
      Postgrex.query!(conn, "CREATE EXTENSION IF NOT EXISTS pg_trgm", [])
      Postgrex.stop(conn)
    end),
    shared: true

  setup %{postgres: pg} do
    opts = TestcontainerEx.Container.Info.pg_connect_opts(pg)
    {:ok, conn} = Postgrex.start_link(opts)
    {:ok, %{conn: conn}}
  end

  test "inserts and queries data", %{conn: conn} do
    Postgrex.query!(conn, "INSERT INTO users (name) VALUES ($1)", ["Alice"])
    assert [%{"name" => "Alice"}] =
      Postrex.query!(conn, "SELECT * FROM users WHERE name = $1", ["Alice"])
  end
end
```
