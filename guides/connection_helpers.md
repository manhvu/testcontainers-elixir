# Connection Helpers

TestcontainerEx provides convenience functions for extracting runtime connection information from started containers. These helpers eliminate the need to manually parse host, port, username, and password.

## Quick Connection Setup

```elixir
{:ok, container} = TestcontainerEx.start_container(TestcontainerEx.PostgresContainer.new())

# Get Postgrex-compatible connection options
opts = TestcontainerEx.Container.Info.pg_connect_opts(container)
# => [hostname: "localhost", port: 55123, username: "test", password: "test", database: "test"]

{:ok, conn} = Postgrex.start_link(opts)
```

## Available Helpers

### PostgreSQL

```elixir
# Returns keyword list for Postgrex.start_link/1
TestcontainerEx.Container.Info.pg_connect_opts(container)
# => [hostname: "localhost", port: 55123, username: "test", password: "test", database: "test"]

# With overrides
TestcontainerEx.Container.Info.pg_connect_opts(container, database: "my_other_db")
# => [hostname: "localhost", port: 55123, username: "test", password: "test", database: "my_other_db"]
```

### MySQL

```elixir
# Returns keyword list for MyXQL.start_link/1
TestcontainerEx.Container.Info.mysql_connect_opts(container)
# => [hostname: "localhost", port: 55124, username: "test", password: "test", database: "test"]
```

### Redis

```elixir
# Returns a Redis connection URL
TestcontainerEx.Container.Info.redis_url(container)
# => "redis://localhost:55125"

# With password
TestcontainerEx.Container.Info.redis_url(container)
# => "redis://:secret@localhost:55125"
```

### MongoDB

```elixir
# Returns a MongoDB connection URL
TestcontainerEx.Container.Info.mongo_url(container)
# => "mongodb://root:example@localhost:55126/mydb"
```

### RabbitMQ (AMQP)

```elixir
# Returns an AMQP connection URL
TestcontainerEx.Container.Info.amqp_url(container)
# => "amqp://guest:guest@localhost:55127/"
```

### Generic URL Builder

```elixir
# Build a URL for any TCP service
TestcontainerEx.Container.Info.url(container, 9042, "cassandra")
# => "cassandra://localhost:55128"

TestcontainerEx.Container.Info.url(container, 9200, "http")
# => "http://localhost:55129"
```

### Host and Port

```elixir
# Get the host address
TestcontainerEx.Container.Info.host(container)
# => "localhost"

# Get the mapped host port for a container port
TestcontainerEx.Container.Info.port(container, 5432)
# => 55123
```

## CustomContainer Helpers

`CustomContainer` provides additional helpers for connection management:

```elixir
alias TestcontainerEx.CustomContainer

config =
  CustomContainer.new("my-app:latest")
  |> CustomContainer.with_exposed_port(8080)
  |> CustomContainer.with_exposed_port(5432)

{:ok, container} = TestcontainerEx.start_container(config)

# Get host:port tuple
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

## Runtime Info

Get a complete map of container runtime details:

```elixir
info = CustomContainer.runtime_info(container)
# %{
#   container_id: "abc123...",
#   image: "my-app:latest",
#   name: "my-app",
#   ip_address: "172.17.0.3",
#   ports: [{8080, 55123}, {5432, 55124}],
#   environment: %{"DATABASE_URL" => "..."},
#   labels: %{"env" => "test"},
#   network: "bridge",
#   network_mode: nil,
#   hostname: "my-app"
# }
```

## Predefined Container Helpers

Each predefined container module provides its own connection helpers:

```elixir
# PostgreSQL
container = TestcontainerEx.start_container!(TestcontainerEx.PostgresContainer.new())
opts = TestcontainerEx.PostgresContainer.connection_parameters(container)
# => [hostname: "localhost", port: 55123, username: "test", ...]

# Redis
container = TestcontainerEx.start_container!(TestcontainerEx.RedisContainer.new())
url = TestcontainerEx.RedisContainer.connection_url(container)
# => "redis://localhost:55124/"

# Get the mapped port
port = TestcontainerEx.RedisContainer.port(container)
# => 55124
```

## Environment Variable Parsing

Connection helpers automatically extract credentials from container environment variables:

| Helper | Required Env Vars |
|--------|-------------------|
| `pg_connect_opts/1` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` |
| `mysql_connect_opts/1` | `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` |
| `redis_url/1` | `REDIS_PASSWORD` (optional) |
| `mongo_url/1` | `MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD`, `MONGO_INITDB_DATABASE` |
| `amqp_url/1` | `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS`, `RABBITMQ_DEFAULT_VHOST` |

## Custom Connection URLs

For services not covered by built-in helpers, use the generic URL builder:

```elixir
# Elasticsearch
url = TestcontainerEx.Container.Info.url(container, 9200, "http")
# => "http://localhost:55125"

# Kafka
url = TestcontainerEx.Container.Info.url(container, 9092, "kafka")
# => "kafka://localhost:55126"

# Custom scheme with auth
url = CustomContainer.endpoint_url(container, 8080, "https",
  username: "admin", password: "secret"
)
# => "https://admin:secret@localhost:55127"
```

## ExUnit Pattern

A common pattern for integration tests:

```elixir
defmodule MyApp.DatabaseTest do
  use ExUnit.Case
  import TestcontainerEx.ExUnit

  container :postgres,
    CustomContainer.new("postgres:15-alpine")
    |> CustomContainer.with_exposed_port(5432)
    |> CustomContainer.with_env("POSTGRES_PASSWORD", "test")
    |> CustomContainer.with_env("POSTGRES_DB", "myapp_test")
    |> CustomContainer.with_wait_strategy(
      TestcontainerEx.Wait.command(["pg_isready", "-U", "postgres"], 60_000)
    ),
    shared: true

  setup %{postgres: pg} do
    opts = TestcontainerEx.Container.Info.pg_connect_opts(pg)
    {:ok, conn} = Postgrex.start_link(opts)
    {:ok, %{conn: conn}}
  end

  test "queries work", %{conn: conn} do
    assert Postgrex.query!(conn, "SELECT 1", []).rows == [[1]]
  end
end
```
