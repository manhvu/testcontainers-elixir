defmodule TestcontainerEx.Connection.Strategies.Dotenv do
  @moduledoc """
  Resolves the container engine host from a `.env` file in the project root.

  Reads `CONTAINER_ENGINE_HOST` from `.env` (if present) so that developers can
  commit a project-local default without modifying their shell profile.

  Only activates when neither `CONTAINER_ENGINE_HOST` nor `DOCKER_HOST` is
  already set in the environment, making this a fallback rather than an
  override.

  The `.env` file uses simple `KEY=VALUE` syntax, one per line.
  Lines starting with `#` are treated as comments.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  @default_file ".env"
  @primary_key "CONTAINER_ENGINE_HOST"
  @fallback_key "DOCKER_HOST"

  require Logger

  alias TestcontainerEx.Connection.Url

  @impl true
  def resolve do
    # Only consult .env when neither env var is already set
    case {System.get_env(@primary_key), System.get_env(@fallback_key)} do
      {nil, nil} ->
        read_from_dotenv()

      {"", _} ->
        read_from_dotenv()

      {nil, ""} ->
        read_from_dotenv()

      {url, _} when is_binary(url) and url != "" ->
        {:error, {:env_already_set, @primary_key, url}}

      {nil, url} when is_binary(url) and url != "" ->
        {:error, {:env_already_set, @fallback_key, url}}

      _ ->
        read_from_dotenv()
    end
  end

  defp read_from_dotenv do
    path = Path.join(File.cwd!(), @default_file)

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          parsed = parse_env(content)

          case Map.get(parsed, @primary_key) do
            url when is_binary(url) and url != "" ->
              Logger.info("Read #{@primary_key} from #{@default_file}: #{url}")
              probe(url)

            _ ->
              {:error, {:key_not_found_in_file, @primary_key, path}}
          end

        {:error, reason} ->
          {:error, {:file_read_failed, path, reason}}
      end
    else
      {:error, {:file_not_found, path}}
    end
  end

  defp parse_env(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.flat_map(&parse_line/1)
    |> Map.new()
  end

  defp parse_line(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] when is_binary(value) ->
        [{String.trim(key), String.trim(value)}]

      _ ->
        []
    end
  end

  defp probe(url) do
    case URI.parse(url) do
      %URI{scheme: "unix", path: path} ->
        if socket_accessible?(path) do
          Logger.info("Container engine host detected via .env: #{url}")
          {:ok, url}
        else
          {:error, {:socket_not_found, path}}
        end

      _ ->
        case Req.get("#{Url.construct(url)}/_ping") do
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
