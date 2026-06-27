defmodule TestcontainerEx.Connection.Ssl do
  @moduledoc """
  TLS/SSL option building for container engine connections.

  Loads `ca.pem`, `cert.pem`, and `key.pem` from `DOCKER_CERT_PATH`
  (falling back to `~/.docker`). Missing files are skipped.
  """

  alias TestcontainerEx.Connection.Url

  @doc """
  Builds the `:ssl_options` keyword list for a TLS-secured connection.
  """
  @spec build_options() :: keyword()
  def build_options do
    cert_dir = cert_dir()
    ssl_options = [verify: verify_mode()]

    ssl_options
    |> maybe_put_file(:cacertfile, Path.join(cert_dir, "ca.pem"))
    |> maybe_put_file(:certfile, Path.join(cert_dir, "cert.pem"))
    |> maybe_put_file(:keyfile, Path.join(cert_dir, "key.pem"))
  end

  @doc """
  Returns the certificate directory, respecting `DOCKER_CERT_PATH`.
  Falls back to `~/.docker` when unset.
  """
  @spec cert_dir() :: String.t()
  def cert_dir do
    case System.get_env("DOCKER_CERT_PATH") do
      nil -> Path.expand("~/.docker")
      "" -> Path.expand("~/.docker")
      path -> path
    end
  end

  @doc """
  Returns the verify mode based on `DOCKER_TLS_VERIFY`.
  """
  @spec verify_mode() :: :verify_peer | :verify_none
  def verify_mode do
    if Url.tls_verify?() do
      :verify_peer
    else
      require Logger

      Logger.warning(
        "Docker TLS connection without DOCKER_TLS_VERIFY; peer certificate will NOT be verified"
      )

      :verify_none
    end
  end

  defp maybe_put_file(opts, key, path) do
    if File.exists?(path) do
      Keyword.put(opts, key, path)
    else
      require Logger
      Logger.debug("Docker TLS cert file #{path} not found; skipping #{key}")
      opts
    end
  end
end
