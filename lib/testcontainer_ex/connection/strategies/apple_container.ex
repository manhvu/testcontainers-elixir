defmodule TestcontainerEx.Connection.Strategies.AppleContainer do
  @moduledoc """
  Resolves the container engine host for Apple Container (https://github.com/apple/container).

  Apple Container is a macOS-native container runtime for Apple silicon Macs.
  It uses the `container` CLI to manage containers via XPC rather than a
  traditional Docker-compatible HTTP API.

  This strategy activates when:
  - The `container` binary is available on PATH
  - The Apple Container system service is running (`container system status` succeeds)

  The strategy returns a special URL scheme `apple-container://` that downstream
  code can use to route operations through the `container` CLI instead of the
  Docker HTTP API.

  ## Configuration

  No special configuration is required beyond having `container` installed and
  running on an Apple silicon Mac. The socket path used by the Apple Container
  API server is:

      /var/run/com.apple.container.apiserver

  ## Environment variables

  - `CONTAINER_BIN` — override the path to the `container` binary
    (default: searches PATH for `container`)
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  require Logger

  @default_bin "container"
  @apple_container_url "apple-container://"
  @apple_container_socket "/var/run/com.apple.container.apiserver"

  @impl true
  def resolve do
    with {:ok, bin} <- find_binary(),
         :ok <- verify_running(bin) do
      Logger.info("Container engine detected via Apple Container: #{@apple_container_url}")
      {:ok, @apple_container_url}
    end
  end

  defp find_binary do
    case System.get_env("CONTAINER_BIN") do
      nil ->
        case System.find_executable(@default_bin) do
          nil -> {:error, :apple_container_not_installed}
          bin -> {:ok, bin}
        end

      "" ->
        {:error, :apple_container_not_installed}

      bin ->
        if File.exists?(bin) do
          {:ok, bin}
        else
          {:error, {:apple_container_bin_not_found, bin}}
        end
    end
  end

  defp verify_running(bin) do
    with {output, 0} <- System.cmd(bin, ["system", "status"], stderr_to_stdout: true),
         true <- String.contains?(output, "running") or String.contains?(output, "Running"),
         true <- File.exists?(@apple_container_socket) do
      :ok
    else
      false -> {:error, :apple_container_not_running}
      {_output, _exit_code} -> {:error, :apple_container_not_running}
    end
  rescue
    ErlangError -> {:error, :apple_container_not_running}
  end
end
