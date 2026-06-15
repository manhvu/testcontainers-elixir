defmodule TestcontainerEx.Connection do
  @moduledoc """
  Builds an Req client connected to the container engine.

  Composes URL resolution, SSL configuration, and HTTP client setup.
  """

  require Logger

  alias TestcontainerEx.Connection.{Resolver, Ssl, Url}
  alias TestcontainerEx.Util.Constants

  @default_recv_timeout 300_000

  @doc """
  Builds an Req client connected to the detected container engine.

  Returns `{conn, url, raw_url}` where:
  - `conn` is a configured Req request struct
  - `url` is the base URL
  - `raw_url` is the original URL string
  """
  @spec get_connection(keyword()) ::
          {Req.Request.t(), String.t(), String.t()} | {:error, String.t()}
  def get_connection(options \\ []) do
    case Resolver.resolve(options) do
      {:ok, resolved} ->
        url = Url.construct(resolved)
        Logger.info("Container engine host: #{inspect(url, pretty: false)}")

        req_options =
          options
          |> Keyword.merge(
            base_url: url,
            recv_timeout: Keyword.get(options, :recv_timeout, @default_recv_timeout),
            user_agent: Keyword.get(options, :user_agent, Constants.user_agent())
          )

        {build_client(req_options), url, resolved}

      {:error, reasons} ->
        {:error, format_errors(reasons)}
    end
  end

  @doc """
  Builds SSL options for TLS-secured connections.
  Delegates to `TestcontainerEx.Connection.Ssl`.
  """
  @spec build_ssl_options() :: keyword()
  def build_ssl_options, do: Ssl.build_options()

  @doc false
  @spec build_client(keyword()) :: Req.Request.t()
  def build_client(options) do
    base_url = Keyword.get(options, :base_url)
    user_agent = Keyword.get(options, :user_agent, Constants.user_agent())
    recv_timeout = Keyword.get(options, :recv_timeout, @default_recv_timeout)

    uri = URI.parse(base_url)

    {req_base_url, unix_socket} =
      case uri do
        %URI{scheme: "http+unix"} ->
          {"http://localhost", decode_unix_socket_path(uri)}

        _ ->
          {base_url, nil}
      end

    transport_opts =
      if Url.https?(base_url) do
        Ssl.build_options()
      else
        []
      end

    req_options =
      [
        base_url: req_base_url,
        user_agent: user_agent,
        receive_timeout: recv_timeout,
        unix_socket: unix_socket
      ] ++
        if transport_opts == [], do: [], else: [connect_options: [transport_opts: transport_opts]]

    Req.new(req_options)
  end

  defp decode_unix_socket_path(%URI{authority: nil, path: path}) do
    URI.decode(path)
  end

  defp decode_unix_socket_path(%URI{authority: authority}) do
    URI.decode_www_form(authority)
  end

  defp format_errors(errors) do
    """
    Failed to find a container engine host.

    Resolution attempted the following strategies, all of which failed:
    #{format_error_list(errors)}

    To fix this, ensure one of the following:
      1. Docker Desktop, Colima, Podman, or Apple Container is running
      2. CONTAINER_ENGINE environment variable is set (e.g. `CONTAINER_ENGINE=docker`)
      3. CONTAINER_ENGINE_HOST environment variable is set correctly
      4. A .env file with CONTAINER_ENGINE_HOST exists in the project root
      5. A container engine socket exists at a standard path (e.g. /var/run/docker.sock)

    For Colima users:
      colima start
      # Verify with: docker ps

    For Apple Container users (macOS 26+, Apple silicon):
      container system start
      # Verify with: container system status
    """
  end

  defp format_error_list(errors) do
    Enum.map_join(errors, "\n", fn error -> "  - #{format_reason(error)}" end)
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

  defp format_reason(:apple_container_not_installed) do
    "Apple Container not installed (https://github.com/apple/container)"
  end

  defp format_reason(:apple_container_not_running) do
    "Apple Container not running (container system start)"
  end

  defp format_reason({:apple_container_bin_not_found, path}) do
    "CONTAINER_BIN points to non-existent file: #{path}"
  end

  defp format_reason(other) do
    inspect(other)
  end
end
