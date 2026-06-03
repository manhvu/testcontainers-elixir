defmodule TestcontainerEx.Connection.Strategies.Dotenv do
  @moduledoc """
  Resolves the container engine host from a `.env` file in the project root.

  Reads `DOCKER_HOST` from `.env` (if present) so that developers can
  commit a project-local default without modifying their shell profile.
  Only activates when `DOCKER_HOST` is *not* already set in the environment,
  making this a fallback rather than an override.

  The `.env` file uses simple `KEY=VALUE` syntax, one per line.
  Lines starting with `#` are treated as comments.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  @default_file ".env"
  @key "DOCKER_HOST"

  require Logger

  @impl true
  def resolve do
    # Only consult .env when the env var is not already set
    case System.get_env(@key) do
      nil ->
        read_from_dotenv()

      "" ->
        read_from_dotenv()

      env_url ->
        # Already set in the environment — skip .env and let the Env strategy handle it
        {:error, {:env_already_set, @key, env_url}}
    end
  end

  defp read_from_dotenv do
    path = Path.join(File.cwd!(), @default_file)

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case parse_env(content) do
            %{@key => url} when is_binary(url) and url != "" ->
              Logger.info("Read DOCKER_HOST from #{@default_file}: #{url}")
              probe(url)

            _ ->
              {:error, {:key_not_found_in_file, @key, path}}
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
    case Tesla.get(test_client(), "#{TestcontainerEx.Connection.Url.construct(url)}/_ping") do
      {:ok, _} -> {:ok, url}
      {:error, reason} -> {:error, {:ping_failed, url, reason}}
    end
  end

  defp test_client, do: Tesla.client([], Tesla.Adapter.Hackney)
end
