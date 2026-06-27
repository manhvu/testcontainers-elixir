defmodule TestcontainerEx.Error do
  @moduledoc """
  Structured error type returned by all public TestcontainerEx functions.

  Pattern-match on `:code` to handle specific failure modes:

      case TestcontainerEx.start_container(config) do
        {:ok, container} -> container
        {:error, %TestcontainerEx.Error{code: :timeout}} -> handle_timeout()
        {:error, %TestcontainerEx.Error{code: :pull_failed} = err} ->
          Logger.error("Pull failed: \#{err.message}")
      end
  """

  @type code ::
          :timeout
          | :pull_failed
          | :container_start_failed
          | :wait_strategy_failed
          | :connection_refused
          | :docker_api_error
          | :image_not_found
          | :not_connected
          | :port_not_mapped

  @type t :: %__MODULE__{
          code: code(),
          message: String.t(),
          context: map(),
          cause: any()
        }

  defstruct [:code, :message, context: %{}, cause: nil]

  @doc "Build a timeout error with optional context."
  @spec timeout(String.t(), map()) :: t()
  def timeout(message, context \\ %{}) do
    %__MODULE__{code: :timeout, message: message, context: context}
  end

  @doc "Build a pull failure error."
  @spec pull_failed(String.t(), any()) :: t()
  def pull_failed(image, cause) do
    %__MODULE__{
      code: :pull_failed,
      message: "Failed to pull image #{image}",
      context: %{image: image},
      cause: cause
    }
  end

  @doc "Build a wait-strategy failure, including the last container logs."
  @spec wait_strategy_failed(atom() | struct(), integer(), [String.t()]) :: t()
  def wait_strategy_failed(strategy, elapsed_ms, last_logs \\ []) do
    %__MODULE__{
      code: :wait_strategy_failed,
      message: "Wait strategy #{inspect(strategy)} timed out after #{elapsed_ms}ms",
      context: %{strategy: strategy, elapsed_ms: elapsed_ms, last_logs: last_logs}
    }
  end

  @doc "Build a Docker API error."
  @spec docker_api_error(String.t(), any()) :: t()
  def docker_api_error(message, cause \\ nil) do
    %__MODULE__{code: :docker_api_error, message: message, cause: cause}
  end

  @doc "Build a not-connected error."
  @spec not_connected() :: t()
  def not_connected do
    %__MODULE__{code: :not_connected, message: "Not connected to container engine"}
  end

  @doc "Build a port-not-mapped error."
  @spec port_not_mapped(integer()) :: t()
  def port_not_mapped(port) do
    %__MODULE__{
      code: :port_not_mapped,
      message: "Port #{port} is not mapped",
      context: %{port: port}
    }
  end

  @doc "Wrap an arbitrary error term into a TestcontainerEx.Error if not already one."
  @spec wrap(any()) :: t()
  def wrap(%__MODULE__{} = err), do: err

  def wrap(reason),
    do: %__MODULE__{code: :docker_api_error, message: inspect(reason), cause: reason}
end
