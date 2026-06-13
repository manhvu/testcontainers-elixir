defmodule TestcontainerEx.Connection.Resolver do
  @moduledoc """
  Orchestrates host resolution strategies.

  When an explicit engine is requested, only that strategy is tried.
  When `:auto` (default), tries all strategies in priority order until one succeeds.

  Returns `{:ok, url}` or `{:error, reasons}`.
  """

  alias TestcontainerEx.Connection.Strategies

  @type engine ::
          :auto
          | :docker
          | :podman
          | :colima
          | :minikube
          | :apple_container

  # Default auto-detection order.
  # Apple Container is placed late because it requires the `container` binary
  # and socket to both be present; without that check it can claim the engine
  # even when Docker/Colima is the intended runtime.
  @strategies [
    Strategies.Properties,
    Strategies.Env,
    Strategies.Dotenv,
    Strategies.ContainerEnv,
    Strategies.Colima,
    Strategies.Socket,
    Strategies.Minikube,
    Strategies.AppleContainer
  ]

  # Map engine atoms to their strategy modules.
  @engine_strategies %{
    docker: [Strategies.Socket, Strategies.Colima, Strategies.ContainerEnv],
    podman: [Strategies.Socket, Strategies.ContainerEnv],
    colima: [Strategies.Colima],
    minikube: [Strategies.Minikube],
    apple_container: [Strategies.AppleContainer]
  }

  @doc """
  Resolves the container engine host URL.

  ## Options

    * `:engine` — explicitly select an engine:
      * `:auto` (default) — try all strategies in priority order
      * `:docker` — Docker Desktop, Colima, or socket-based Docker
      * `:podman` — Podman socket or container env
      * `:colima` — Colima only
      * `:minikube` — Minikube only
      * `:apple_container` — Apple Container only

  The engine can also be set via the `CONTAINER_ENGINE` environment variable
  (e.g. `CONTAINER_ENGINE=docker`). The explicit option takes precedence.
  """
  @spec resolve(keyword()) :: {:ok, String.t()} | {:error, [term()]}
  def resolve(options \\ []) do
    engine = Keyword.get(options, :engine, engine_from_env())

    strategies =
      case engine do
        :auto -> @strategies
        atom when is_atom(atom) -> Map.get(@engine_strategies, atom, @strategies)
      end

    do_resolve(strategies, [])
  end

  defp engine_from_env do
    case System.get_env("CONTAINER_ENGINE") do
      nil -> :auto
      "" -> :auto
      "auto" -> :auto
      "docker" -> :docker
      "podman" -> :podman
      "colima" -> :colima
      "minikube" -> :minikube
      "apple_container" -> :apple_container
      _ -> :auto
    end
  end

  defp do_resolve([], errors), do: {:error, Enum.reverse(errors)}

  defp do_resolve([strategy | rest], errors) do
    case strategy.resolve() do
      {:ok, url} -> {:ok, url}
      {:error, reason} -> do_resolve(rest, [reason | errors])
    end
  end
end
