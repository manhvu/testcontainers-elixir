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
        case Keyword.get(options, :ssl_options) do
          nil ->
            {Tesla.Adapter.Hackney, recv_timeout: recv_timeout}

          ssl_opts ->
            {Tesla.Adapter.Hackney, recv_timeout: recv_timeout, ssl_options: ssl_opts}
        end

      adapter ->
        adapter
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

  defp format_errors(errors) do
    "Failed to find docker host: #{inspect(errors)}"
  end
end
