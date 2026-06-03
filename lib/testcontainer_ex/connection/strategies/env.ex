defmodule TestcontainerEx.Connection.Strategies.Env do
  @moduledoc """
  Resolves the container engine host from the `DOCKER_HOST` environment variable.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  @default_key "DOCKER_HOST"

  @impl true
  def resolve do
    case System.get_env(@default_key) do
      nil ->
        {:error, {:not_found, @default_key}}

      "" ->
        {:error, {:empty, @default_key}}

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
