defmodule TestcontainerEx.Recon do
  @moduledoc """
  Debugging helpers powered by `:recon` (Erlang runtime inspection).

  This module is only available in `:dev` and `:test` environments.
  It provides convenient Elixir wrappers around common `:recon` operations
  for inspecting the TestcontainerEx GenServer, processes, and memory.

  ## Prerequisites

  Add `:recon` to your dependencies (already included in dev/test):

      {:recon, "~> 2.5", only: [:dev, :test]}

  ## Usage (from `iex -S mix`)

      # Show top processes by memory
      TestcontainerEx.Recon.top_processes()

      # Inspect the TestcontainerEx GenServer state
      TestcontainerEx.Recon.server_state()

      # Show process info for the GenServer
      TestcontainerEx.Recon.server_info()
  """

  @server_name TestcontainerEx.Server

  @compile {:no_warn_undefined, [{:recon, :proc_window, 3}, {:recon_alloc, :memory, 1}]}

  @doc """
  Returns the current state of the TestcontainerEx GenServer.

  Useful for debugging from IEx to see tracked containers, networks,
  and compose environments.
  """
  @spec server_state() :: map() | {:error, :not_running}
  def server_state do
    case Process.whereis(@server_name) do
      nil -> {:error, :not_running}
      pid -> :sys.get_state(pid)
    end
  end

  @doc """
  Returns process info for the TestcontainerEx GenServer.
  """
  @spec server_info() :: [{atom(), term()}] | {:error, :not_running}
  def server_info do
    case Process.whereis(@server_name) do
      nil -> {:error, :not_running}
      pid -> Process.info(pid)
    end
  end

  @doc """
  Returns the top N processes sorted by memory usage.

  Uses `:recon.proc_windows/2` when available, falls back to a simple
  implementation otherwise.
  """
  @spec top_processes(pos_integer()) :: [{pid(), term()}]
  def top_processes(n \\ 10) when is_integer(n) and n > 0 do
    :recon.proc_window(:memory, n, 1)
  rescue
    _ ->
      # Fallback if recon isn't loaded
      Process.list()
      |> Enum.map(fn pid -> {pid, Process.info(pid, :memory)} end)
      |> Enum.filter(fn {_, info} -> info != nil end)
      |> Enum.sort_by(fn {_, {:memory, m}} -> m end, :desc)
      |> Enum.take(n)
  end

  @doc """
  Returns memory allocation breakdown for the node.
  """
  @spec memory() :: [{atom(), non_neg_integer()}]
  def memory do
    :recon_alloc.memory(:used)
  rescue
    _ -> :erlang.memory()
  end

  @doc """
  Returns a summary of the TestcontainerEx server's tracked resources.

  More readable than `server_state/0` — shows counts and names rather
  than the full state struct.
  """
  @spec resource_summary() :: map() | {:error, :not_running}
  def resource_summary do
    case server_state() do
      {:error, _} = err ->
        err

      state ->
        %{
          containers: MapSet.to_list(state.containers),
          container_count: MapSet.size(state.containers),
          networks: MapSet.to_list(state.networks),
          network_count: MapSet.size(state.networks),
          images: MapSet.to_list(state.images),
          image_count: MapSet.size(state.images),
          compose_env_count: length(state.compose_envs),
          connected: !is_nil(state.conn),
          docker_hostname: state.docker_hostname,
          use_container_ip: state.use_container_ip
        }
    end
  end
end
