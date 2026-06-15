defmodule TestcontainerEx.Connection.Strategies.Env do
  @moduledoc """
  Resolves the container engine host from the `CONTAINER_ENGINE_HOST`
  environment variable.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  @primary_key "CONTAINER_ENGINE_HOST"

  @impl true
  def resolve do
    case System.get_env(@primary_key) do
      nil ->
        {:error, {:not_found, @primary_key}}

      "" ->
        {:error, {:empty, @primary_key}}

      url when is_binary(url) and url != "" ->
        probe(url)

      _ ->
        {:error, {:empty, @primary_key}}
    end
  end

  defp probe(url) do
    case URI.parse(url) do
      %URI{scheme: "unix", path: path} ->
        if socket_accessible?(path) do
          require Logger
          Logger.info("Container engine host detected via #{@primary_key}: #{url}")
          {:ok, url}
        else
          {:error, {:socket_not_found, path}}
        end

      _ ->
        case Req.get("#{TestcontainerEx.Connection.Url.construct(url)}/_ping") do
          {:ok, %{status: 200}} -> {:ok, url}
          {:error, reason} -> {:error, {:ping_failed, url, reason}}
        end
    end
  end

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
