defmodule TestcontainerEx.Connection do
  @moduledoc """
  Builds a Tesla client connected to the container engine.

  Composes URL resolution, SSL configuration, and HTTP client setup.
  """

  require Logger

  alias DockerEngineAPI.Connection, as: ApiConnection
  alias TestcontainerEx.Connection.{Resolver, Ssl, Url}
  alias TestcontainerEx.Util.Constants

  @timeout 300_000

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
        recv_timeout: @timeout,
        user_agent: Constants.user_agent()
      )
      |> maybe_add_tls_options(url)

    {ApiConnection.new(conn_options), url, raw_url}
  end

  @doc """
  Builds SSL options for TLS-secured connections.
  Delegates to `TestcontainerEx.Connection.Ssl`.
  """
  @spec build_ssl_options() :: keyword()
  def build_ssl_options, do: Ssl.build_options()

  # ── Private ───────────────────────────────────────────────────────

  defp maybe_add_tls_options(options, url) do
    if Url.https?(url) do
      ssl_options = Ssl.build_options()

      adapter_opts = [
        recv_timeout: Keyword.get(options, :recv_timeout, @timeout),
        ssl_options: ssl_options
      ]

      Keyword.put(options, :adapter, {Tesla.Adapter.Hackney, adapter_opts})
    else
      options
    end
  end

  defp format_errors(errors) do
    "Failed to find docker host: #{inspect(errors)}"
  end
end
