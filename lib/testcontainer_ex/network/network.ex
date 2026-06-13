defmodule TestcontainerEx.Network do
  @moduledoc """
  Docker network operations.
  """

  require Logger

  alias TestcontainerEx.Engine.Api
  alias TestcontainerEx.Telemetry

  @doc """
  Creates a Docker network. Returns `{:ok, id}` or `{:ok, :already_exists}`.
  Retries on transient errors.
  """
  @spec create(String.t(), Req.Request.t()) ::
          {:ok, String.t()} | {:ok, :already_exists} | {:error, term()}
  def create(name, conn) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :network, :create],
      %{network_name: name},
      fn -> retry_network(fn -> Api.create_network(name, conn) end, 2) end
    )
  end

  @doc """
  Removes a Docker network.
  """
  @spec remove(String.t(), Req.Request.t()) :: :ok | {:error, term()}
  def remove(name, conn) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :network, :remove],
      %{network_name: name},
      fn -> Api.remove_network(name, conn) end
    )
  end

  # Retry network operations on transient Docker daemon errors.
  defp retry_network(fun, retries_left)

  defp retry_network(fun, 0), do: fun.()

  defp retry_network(fun, retries_left) do
    case fun.() do
      {:error, :econnrefused} ->
        Logger.debug("Network operation got econnrefused, retrying in 500ms...")
        :timer.sleep(500)
        retry_network(fun, retries_left - 1)

      {:error, {:http_error, 500}} ->
        Logger.debug("Network operation got HTTP 500, retrying in 1000ms...")
        :timer.sleep(1000)
        retry_network(fun, retries_left - 1)

      other ->
        other
    end
  end

  @doc """
  Checks if a network exists.
  """
  @spec exists?(String.t(), Req.Request.t()) :: boolean()
  def exists?(name, conn) do
    Api.network_exists?(name, conn)
  end

  @doc """
  Inspects the default bridge network and returns its gateway IP.
  Used for Docker-outside-of-Docker (DooD) detection.
  """
  @spec bridge_gateway(Req.Request.t()) :: {:ok, String.t()} | {:error, term()}
  def bridge_gateway(conn) do
    Api.get_bridge_gateway(conn)
  end
end
