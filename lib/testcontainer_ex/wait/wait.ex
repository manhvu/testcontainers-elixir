defmodule TestcontainerEx.Wait do
  @moduledoc """
  Convenience aliases for all wait strategies.

  Instead of importing individual strategy modules, you can use this single
  module to access all wait strategies:

      import TestcontainerEx.Wait

      # Equivalent to:
      # import TestcontainerEx.PortWaitStrategy
      # import TestcontainerEx.HttpWaitStrategy
      # import TestcontainerEx.LogWaitStrategy
      # import TestcontainerEx.CommandWaitStrategy

  ## Strategies

  | Strategy              | Ready when...                      |
  |-----------------------|------------------------------------|
  | `PortWaitStrategy`    | a TCP port accepts connections     |
  | `HttpWaitStrategy`    | an HTTP request succeeds           |
  | `LogWaitStrategy`     | a log line matches a regex         |
  | `CommandWaitStrategy` | a command exits with code 0        |
  """

  defdelegate port(ip, port, timeout \\ 5000, retry_delay \\ 200),
    to: TestcontainerEx.PortWaitStrategy,
    as: :new

  defdelegate http(endpoint, port, options \\ []),
    to: TestcontainerEx.HttpWaitStrategy,
    as: :new

  defdelegate log(log_regex, timeout \\ 5000, retry_delay \\ 200),
    to: TestcontainerEx.LogWaitStrategy,
    as: :new

  defdelegate command(command, timeout \\ 5000, retry_delay \\ 200),
    to: TestcontainerEx.CommandWaitStrategy,
    as: :new
end
