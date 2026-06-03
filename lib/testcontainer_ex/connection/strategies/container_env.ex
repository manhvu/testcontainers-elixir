defmodule TestcontainerEx.Connection.Strategies.ContainerEnv do
  @moduledoc """
  Resolves the container engine host from the `CONTAINER_HOST` environment variable.

  Podman uses `CONTAINER_HOST` as the equivalent of Docker's `DOCKER_HOST`.
  When set, it points to the Podman service socket, e.g.
  `unix:///run/user/1000/podman/podman.sock`.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  @key "CONTAINER_HOST"

  @impl true
  def resolve do
    case System.get_env(@key) do
      nil ->
        {:error, {:not_found, @key}}

      "" ->
        {:error, {:empty, @key}}

      url ->
        probe(url)
    end
  end

  defp probe(url) do
    case Tesla.get(test_client(), "#{TestcontainerEx.Connection.Url.construct(url)}/_ping") do
      {:ok, _} -> {:ok, url}
      {:error, reason} -> {:error, {:ping_failed, url, reason}}
    end
  end

  defp test_client, do: Tesla.client([], Tesla.Adapter.Hackney)
end
