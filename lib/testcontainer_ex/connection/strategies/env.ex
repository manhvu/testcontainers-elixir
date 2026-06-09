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
    case URI.parse(url) do
      %URI{scheme: "unix", path: path} ->
        if socket_accessible?(path) do
          require Logger
          Logger.info("Docker host detected via DOCKER_HOST: #{url}")
          {:ok, url}
        else
          {:error, {:socket_not_found, path}}
        end

      _ ->
        case Tesla.get(test_client(), "#{TestcontainerEx.Connection.Url.construct(url)}/_ping") do
          {:ok, _} -> {:ok, url}
          {:error, reason} -> {:error, {:ping_failed, url, reason}}
        end
    end
  end

  defp test_client, do: Tesla.client([], Tesla.Adapter.Hackney)

  # Check if a path is a readable Unix socket.
  # Uses file mode bits (not File.stat type field) because some
  # filesystems (e.g. virtiofs on macOS) report sockets as :other.
  # The Unix socket type is indicated by mode bits 0o140000.
  defp socket_accessible?(path) do
    case File.stat(path) do
      {:ok, stat} -> :erlang.band(stat.mode, 0o170000) == 0o140000
      _ -> false
    end
  end
end
