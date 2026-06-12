defmodule TestcontainerEx.Connection.Strategies.ContainerEnv do
  @moduledoc """
  Resolves the container engine host from Podman-style environment variables.

  Checks `CONTAINER_ENGINE_HOST` first, then `CONTAINER_HOST` for Podman
  compatibility, then falls back to `DOCKER_HOST`.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  @impl true
  def resolve do
    case {System.get_env("CONTAINER_ENGINE_HOST"), System.get_env("CONTAINER_HOST"),
          System.get_env("DOCKER_HOST")} do
      {nil, nil, nil} ->
        {:error, {:not_found, "CONTAINER_ENGINE_HOST"}}

      {"", nil, nil} ->
        {:error, {:empty, "CONTAINER_ENGINE_HOST"}}

      {nil, "", nil} ->
        {:error, {:empty, "CONTAINER_HOST"}}

      {nil, nil, ""} ->
        {:error, {:empty, "DOCKER_HOST"}}

      {url, _, _} when is_binary(url) and url != "" ->
        probe(url)

      {_, url, _} when is_binary(url) and url != "" ->
        probe(url)

      {_, _, url} when is_binary(url) and url != "" ->
        probe(url)

      _ ->
        {:error, {:empty, "CONTAINER_ENGINE_HOST"}}
    end
  end

  defp probe(url) do
    case Req.get("#{TestcontainerEx.Connection.Url.construct(url)}/_ping") do
      {:ok, %{status: 200}} -> {:ok, url}
      {:error, reason} -> {:error, {:ping_failed, url, reason}}
    end
  end
end
