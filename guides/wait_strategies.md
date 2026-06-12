# Wait Strategies

Wait strategies determine when a container is considered "ready". TestcontainerEx provides four built-in strategies and supports combining multiple strategies.

## Quick Reference

| Strategy | Ready when... | Module |
|----------|---------------|--------|
| **Port** | A TCP port accepts connections | `PortWaitStrategy` |
| **HTTP** | An HTTP request succeeds | `HttpWaitStrategy` |
| **Log** | A log line matches a regex | `LogWaitStrategy` |
| **Command** | A command exits with code 0 | `CommandWaitStrategy` |

## Using the Unified Wait Module

The easiest way to create wait strategies:

```elixir
import TestcontainerEx.Wait

# Wait for port 5480 to accept connections (60s timeout)
Wait.port("localhost", 5432, 60_000)

# Wait for an HTTP 200 from /health
Wait.http("/health", 8080, status_code: 200)

# Wait for a log line matching a regex
Wait.log(~r/Server started/, 60_000)

# Wait for a command to succeed
Wait.command(["pg_isready", "-U", "postgres"], 60_000)
```

## Port Wait Strategy

Waits until a TCP port accepts connections:

```elixir
alias TestcontainerEx.PortWaitStrategy

# Basic usage — wait for localhost:5432
PortWaitStrategy.new("localhost", 5432)

# With custom timeout (60s) and retry delay (500ms)
PortWaitStrategy.new("localhost", 5432, 60_000, 500)

# With default timeout (5s) and custom retry delay
PortWaitStrategy.new("localhost", 5432, 5000, 100)
```

## HTTP Wait Strategy

Waits until an HTTP request succeeds:

```elixir
alias TestcontainerEx.HttpWaitStrategy

# Basic — wait for any HTTP response
HttpWaitStrategy.new("/health", 8080)

# Wait for specific status code
HttpWaitStrategy.new("/health", 8080, status_code: 200)

# With custom headers
HttpWaitStrategy.new("/api/ready", 8080,
  status_code: 200,
  headers: [{"authorization", "Bearer token"}]
)

# With custom request method
HttpWaitStrategy.new("/health", 8080,
  method: :head,
  status_code: 200
)

# With a custom matcher function
HttpWaitStrategy.new("/health", 8080,
  match: fn response ->
    response.status == 200 and
      response.body["status"] == "ok"
  end
)

# With protocol and timeout
HttpWaitStrategy.new("/health", 8443,
  protocol: "https",
  status_code: 200,
  timeout: 10_000
)
```

## Log Wait Strategy

Waits until a log line matches a regex:

```elixir
alias TestcontainerEx.LogWaitStrategy

# Wait for "Server started" in logs
LogWaitStrategy.new(~r/Server started/, 60_000)

# Wait for database ready
LogWaitStrategy.new(~r/database system is ready to accept connections/, 120_000)

# With custom retry delay
LogWaitStrategy.new(~r/ready/, 30_000, 500)
```

## Command Wait Strategy

Waits until a command inside the container exits with code 0:

```elixir
alias TestcontainerEx.CommandWaitStrategy

# Wait for PostgreSQL to be ready
CommandWaitStrategy.new(["pg_isready", "-U", "postgres"], 60_000)

# Wait for a custom health check script
CommandWaitStrategy.new(["/app/bin/healthcheck"], 30_000)

# With custom retry delay
CommandWaitStrategy.new(["curl", "-f", "http://localhost:8080/health"], 60_000, 500)
```

## Combining Multiple Strategies

Apply multiple wait strategies to a single container:

```elixir
alias TestcontainerEx.CustomContainer
import TestcontainerEx.Wait

config =
  CustomContainer.new("my-app:latest")
  |> CustomContainer.with_exposed_port(8080)
  |> CustomContainer.with_wait_strategies([
    # First wait for the log
    log(~r/Application started/, 30_000),
    # Then verify the HTTP endpoint
    http("/health", 8080, status_code: 200)
  ])
```

## Predefined Containers with Wait Strategies

Predefined containers come with sensible defaults:

```elixir
# PostgreSQL — waits with pg_isready
TestcontainerEx.PostgresContainer.new()

# Redis — waits with redis-cli PING
TestcontainerEx.RedisContainer.new()

# Override the wait timeout
TestcontainerEx.PostgresContainer.new()
|> TestcontainerEx.PostgresContainer.with_wait_timeout(120_000)
```

## Custom Wait Strategies

Implement your own wait strategy by implementing the `WaitStrategy` protocol:

```elixir
defmodule MyApp.WaitStrategy do
  defstruct [:check_fn, :timeout]

  def new(check_fn, timeout \\ 30_000) do
    %__MODULE__{check_fn: check_fn, timeout: timeout}
  end
end

defimpl TestcontainerEx.WaitStrategy, for: MyApp.WaitStrategy do
  def wait_until_container_is_ready(strategy, container, conn) do
    # Your custom logic here
    # Return :ok when ready, {:error, reason} on failure/timeout
    case strategy.check_fn.(container, conn) do
      :ok -> :ok
      {:error, reason} -> {:error, reason, strategy}
    end
  end
end
```

## Common Patterns

### Database Ready

```elixir
CustomContainer.new("postgres:15-alpine")
|> CustomContainer.with_exposed_port(5432)
|> CustomContainer.with_env("POSTGRES_PASSWORD", "test")
|> CustomContainer.with_wait_strategy(
  TestcontainerEx.CommandWaitStrategy.new(
    ["pg_isready", "-U", "postgres"],
    60_000
  )
)
```

### Web Application Ready

```elixir
CustomContainer.new("my-web-app:latest")
|> CustomContainer.with_exposed_port(8080)
|> CustomContainer.with_wait_strategies([
  TestcontainerEx.LogWaitStrategy.new(~r/Server listening/, 30_000),
  TestcontainerEx.HttpWaitStrategy.new("/health", 8080, status_code: 200)
])
```

### Message Queue Ready

```elixir
CustomContainer.new("rabbitmq:3-management")
|> CustomContainer.with_exposed_port(5672)
|> CustomContainer.with_exposed_port(15672)
|> CustomContainer.with_wait_strategy(
  TestcontainerEx.CommandWaitStrategy.new(
    ["rabbitmq-diagnostics", "-q", "ping"],
    60_000
  )
)
```
