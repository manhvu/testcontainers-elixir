defmodule TestcontainerEx.Connection.Url do
  @moduledoc """
  URL construction and TLS detection for container engine connections.
  """

  @doc """
  Constructs a Tesla-compatible URL from a raw container engine URL.

  - `unix:///path` → `http+unix://<encoded_path>`
  - `tcp://host:port` → `http://` or `https://` (depending on TLS)
  - `https://` / `http://` → passed through
  """
  @spec construct(String.t()) :: String.t()
  def construct(docker_host) do
    case URI.parse(docker_host) do
      %URI{scheme: "unix", path: path} ->
        "http+unix://#{URI.encode_www_form(path)}"

      %URI{scheme: "tcp"} = uri ->
        if tls_verify?() do
          URI.to_string(%{uri | scheme: "https"})
        else
          URI.to_string(%{uri | scheme: "http"})
        end

      %URI{scheme: "https"} = uri ->
        URI.to_string(uri)

      %URI{scheme: "http"} = uri ->
        URI.to_string(uri)

      %URI{scheme: _, authority: _} = uri ->
        URI.to_string(uri)
    end
  end

  @doc """
  Returns true if `DOCKER_TLS_VERIFY` is set to a truthy value.
  """
  @spec tls_verify?() :: boolean()
  def tls_verify? do
    case System.get_env("DOCKER_TLS_VERIFY") do
      "1" -> true
      "true" -> true
      _ -> false
    end
  end

  @doc """
  Returns true if the URL uses the `https` scheme.
  """
  @spec https?(String.t() | any()) :: boolean()
  def https?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https"} -> true
      _ -> false
    end
  end

  def https?(_), do: false
end
