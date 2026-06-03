defmodule TestcontainerEx.Network do
  @moduledoc """
  Docker network operations.
  """

  alias TestcontainerEx.Docker.Api

  @doc """
  Creates a Docker network. Returns `{:ok, id}` or `{:ok, :already_exists}`.
  """
  @spec create(String.t(), Tesla.Env.client()) ::
          {:ok, String.t()} | {:ok, :already_exists} | {:error, term()}
  def create(name, conn) do
    Api.create_network(name, conn)
  end

  @doc """
  Removes a Docker network.
  """
  @spec remove(String.t(), Tesla.Env.client()) :: :ok | {:error, term()}
  def remove(name, conn) do
    Api.remove_network(name, conn)
  end

  @doc """
  Checks if a network exists.
  """
  @spec exists?(String.t(), Tesla.Env.client()) :: boolean()
  def exists?(name, conn) do
    Api.network_exists?(name, conn)
  end

  @doc """
  Inspects the default bridge network and returns its gateway IP.
  Used for Docker-outside-of-Docker (DooD) detection.
  """
  @spec bridge_gateway(Tesla.Env.client()) :: {:ok, String.t()} | {:error, term()}
  def bridge_gateway(conn) do
    Api.get_bridge_gateway(conn)
  end
end
