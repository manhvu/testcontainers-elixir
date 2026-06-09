defmodule TestcontainerEx.Connection do
  @moduledoc """
  Builds a Tesla client connected to the container engine.

  Composes URL resolution, SSL configuration, and HTTP client setup.
  """

  require Logger

  alias TestcontainerEx.Connection.{Resolver, Ssl, Url}
  alias TestcontainerEx.Util.Constants

  @default_recv_timeout 300_000

  @doc """
  Builds a Tesla client connected to the detected container engine.

  Returns `{conn, url, raw_url}` where:
  - `conn` is a configured Tesla client
  - `url` is the Tesla-compatible base URL
  - `raw_url` is the original URL string
  """
  @spec get_connection(keyword()) :: {Tesla.Env.client(), String.t(), String.t()}
  def get_connection(options \\ []) do
    {url, raw_url} =
      case Resolver.resolve() do
        {:ok, resolved} ->
          {Url.construct(resolved), resolved}

        {:error, reasons} ->
          exit(format_errors(reasons))
      end

    Logger.info("Docker host: #{inspect(url, pretty: false)}")

    conn_options =
      options
      |> Keyword.merge(
        base_url: url,
        recv_timeout: Keyword.get(options, :recv_timeout, @default_recv_timeout),
        user_agent: Keyword.get(options, :user_agent, Constants.user_agent())
      )
      |> maybe_add_tls_options(url)
      |> maybe_disable_pool(url)

    {build_client(conn_options), url, raw_url}
  end

  @doc """
  Builds SSL options for TLS-secured connections.
  Delegates to `TestcontainerEx.Connection.Ssl`.
  """
  @spec build_ssl_options() :: keyword()
  def build_ssl_options, do: Ssl.build_options()

  @doc false
  @spec build_client(keyword()) :: Tesla.Env.client()
  def build_client(options) do
    base_url = Keyword.get(options, :base_url)
    user_agent = Keyword.get(options, :user_agent, Constants.user_agent())
    recv_timeout = Keyword.get(options, :recv_timeout, @default_recv_timeout)

    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers, [{"user-agent", user_agent}]},
      Tesla.Middleware.JSON
    ]

    adapter = build_adapter(options, recv_timeout)

    Tesla.client(middleware, adapter)
  end

  @doc false
  @spec build_adapter(keyword(), integer()) :: {module(), keyword()}
  def build_adapter(options, recv_timeout) do
    case Keyword.get(options, :adapter) do
      nil ->
        base_opts = Keyword.put(adapter_opts(options), :recv_timeout, recv_timeout)

        case Keyword.get(options, :ssl_options) do
          nil ->
            {Tesla.Adapter.Hackney, base_opts}

          ssl_opts ->
            {Tesla.Adapter.Hackney, Keyword.put(base_opts, :ssl_options, ssl_opts)}
        end

      adapter ->
        adapter
    end
  end

  # Returns adapter-specific options, including pool settings.
  # Unix socket connections must bypass Hackney's pool (which routes through
  # hackney_happy DNS resolution and returns :nxdomain for local sockets).
  defp adapter_opts(options) do
    case Keyword.get(options, :pool) do
      nil -> []
      pool -> [pool: pool]
    end
  end

  defp maybe_add_tls_options(options, url) do
    if Url.https?(url) do
      ssl_options = Ssl.build_options()
      Keyword.put(options, :ssl_options, ssl_options)
    else
      options
    end
  end

  # Disable Hackney's connection pool for Unix socket URLs.
  # Hackney's pool routes connections through hackney_happy (happy eyeballs
  # DNS resolution), which does not understand Unix domain sockets and returns
  # {:error, :nxdomain}. Direct connections (pool: false) use hackney_local_tcp
  # which correctly calls gen_tcp:connect({:local, Path}, ...).
  defp maybe_disable_pool(options, url) do
    case URI.parse(url) do
      %URI{scheme: "http+unix"} -> Keyword.put(options, :pool, false)
      _ -> options
    end
  end

  defp format_errors(errors) do
    """
    Failed to find a Docker host.

    Resolution attempted the following strategies, all of which failed:
    #{format_error_list(errors)}

    To fix this, ensure one of the following:
      1. Docker Desktop or Colima is running
      2. DOCKER_HOST environment variable is set correctly
      3. A .env file with DOCKER_HOST exists in the project root
      4. A Docker socket exists at a standard path (e.g. /var/run/docker.sock)

    For Colima users:
      colima start
      # Verify with: docker ps
    """
  end

  defp format_error_list(errors) do
    errors
    |> Enum.map(fn error -> "  - #{format_reason(error)}" end)
    |> Enum.join("\n")
  end

  defp format_reason({:not_found, key}), do: "#{key} not found"
  defp format_reason({:empty, key}), do: "#{key} is empty"

  defp format_reason({:ping_failed, url, {:connection_failed, reason}}),
    do: "ping failed for #{url} (connection failed: #{reason})"
  defp format_reason({:ping_failed, url, reason}),
    do: "ping failed for #{url} (#{inspect(reason)})"

  defp format_reason(:no_socket_found), do: "no Docker socket found at standard paths"
  defp format_reason(:all_sockets_failed), do: "all socket pings failed"
  defp format_reason(:minikube_docker_env_failed), do: "minikube docker-env failed"
  defp format_reason(:colima_not_installed), do: "colima not installed (brew install colima)"
  defp format_reason(:colima_not_running), do: "colima not running (colima start)"
  defp format_reason(:colima_socket_not_found), do: "colima status did not report a Docker socket"
  defp format_reason({:colima_socket_unreachable, path, {:connection_failed, reason}}) do
    "colima socket unreachable at #{path} (connection failed: #{reason})"
  end
  defp format_reason({:colima_socket_unreachable, path, reason}) do
    "colima socket unreachable at #{path} (#{inspect(reason)})"
  end

  defp format_reason({:env_already_set, key, _val}) do
    "#{key} already set in ENV (skipped .env)"
  end

  defp format_reason({:key_not_found_in_file, key, path}) do
    "#{key} not found in #{path}"
  end

  defp format_reason({:file_not_found, path}) do
    "file not found: #{path}"
  end

  defp format_reason({:file_read_failed, path, reason}) do
    "failed to read #{path}: #{inspect(reason)}"
  end

  defp format_reason(other) do
    inspect(other)
  end
end
