defmodule TestcontainerEx.Container.Lifecycle do
  @moduledoc """
  Orchestrates container lifecycle: create, start, wait, pull, copy.

  This module is the bridge between the GenServer state and the Docker API.
  All functions require a connection and return `{:ok, container}` or `{:error, reason}`.
  """

  require Logger

  alias TestcontainerEx.{
    Container.BuilderHelper,
    Container.Builder,
    Container.Config,
    Docker.Api,
    Docker.Auth,
    CopyTo,
    PullPolicy,
    Telemetry,
    WaitStrategy
  }

  @doc """
  Creates and starts a container, applying wait strategies.

  Steps:
  1. Build config with labels (via BuilderHelper)
  2. Check for reusable container or create new one
  3. Pull image if needed
  4. Copy files into container
  5. Start container
  6. Apply wait strategies
  7. Call after_start hook
  """
  @spec start_container(struct(), Tesla.Env.client(), map()) ::
          {:ok, Config.t()} | {:error, term()}
  def start_container(builder, conn, state) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :start],
      %{image: extract_image(builder)},
      fn -> do_start_container(builder, conn, state) end
    )
  end

  defp extract_image(%{image: image}) when is_binary(image), do: image
  defp extract_image(_), do: "unknown"

  defp do_start_container(builder, conn, state) do
    case BuilderHelper.build(builder, state) do
      {:reuse, config, hash} ->
        case Api.get_container_by_hash(hash, conn) do
          {:error, :no_container} ->
            Logger.debug("Reusable container not found, creating new one with hash: #{hash}")
            create_and_start(config, builder, conn, state)

          {:error, error} ->
            Logger.debug("Failed to get container by hash: #{inspect(error)}")
            {:error, error}

          {:ok, container} ->
            Logger.debug("Reusing existing container with hash: #{hash}")
            {:ok, container}
        end

      {:noreuse, config, _} ->
        create_and_start(config, builder, conn, state)
    end
  end

  @doc """
  Stops a container by ID.
  """
  @spec stop_container(String.t(), Tesla.Env.client()) :: :ok | {:error, term()}
  def stop_container(container_id, conn) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :stop],
      %{container_id: container_id},
      fn -> Api.stop_container(container_id, conn) end
    )
  end

  # ── Private ───────────────────────────────────────────────────────

  defp create_and_start(config, builder, conn, state) do
    config = resolve_pull_policy(config, state.properties)

    with :ok <- maybe_pull_image(config, conn),
         {:ok, id} <- Api.create_container(config, conn),
         :ok <- copy_to_container(id, config, conn) do
      start_and_wait(id, config, builder, conn)
    end
  end

  def resolve_pull_policy(%Config{pull_policy: nil} = config, properties) do
    policy =
      case Map.get(properties, "pull.policy", "missing") do
        "always" -> PullPolicy.always_pull()
        "never" -> PullPolicy.never_pull()
        _ -> PullPolicy.pull_if_missing()
      end

    %{config | pull_policy: policy}
  end

  def resolve_pull_policy(config, _properties), do: config

  defp start_and_wait(id, config, builder, conn) do
    with :ok <- Api.start_container(id, conn),
         {:ok, container} <- Api.get_container(id, conn),
         :ok <- Builder.after_start(builder, container, conn),
         :ok <- wait_for_container(container, config.wait_strategies, conn) do
      {:ok, container}
    else
      error ->
        Logger.info("Cleaning up container #{id} after failed start")
        Api.stop_container(id, conn)
        error
    end
  end

  defp maybe_pull_image(%{pull_policy: %{always_pull: true}} = config, conn) do
    case pull_with_fallback(config, conn) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp maybe_pull_image(%{pull_policy: %{pull_if_missing: true}} = config, conn) do
    case Api.image_exists?(config.image, conn) do
      {:ok, true} ->
        Logger.debug("Image #{config.image} already present locally, skipping pull")
        :ok

      {:ok, false} ->
        case pull_with_fallback(config, conn) do
          {:ok, _} -> :ok
          error -> error
        end

      error ->
        error
    end
  end

  defp maybe_pull_image(%{pull_policy: %{pull_condition: expr}} = config, conn)
       when is_function(expr) do
    with {:eval, true} <- {:eval, expr.(config, conn)},
         {:ok, _} <- pull_with_fallback(config, conn) do
      :ok
    else
      {:eval, reason} ->
        Logger.debug("Pull policy expression evaluated to: #{inspect(reason)}, skipping pull")
        :ok

      error ->
        error
    end
  end

  defp maybe_pull_image(_config, _conn), do: :ok

  defp pull_with_fallback(config, conn) do
    case resolve_auth(config) do
      {:explicit, auth} ->
        Api.pull_image(config.image, conn, auth: auth)

      {:auto, auth} ->
        case Api.pull_image(config.image, conn, auth: auth) do
          {:error, {:http_error, status}} when status >= 400 and status < 500 ->
            Logger.debug("Auto-resolved auth rejected (HTTP #{status}), retrying without auth")
            Api.pull_image(config.image, conn, auth: nil)

          result ->
            result
        end

      :none ->
        Api.pull_image(config.image, conn, auth: nil)
    end
  end

  defp resolve_auth(%{auth: auth}) when is_binary(auth) and auth != "", do: {:explicit, auth}

  defp resolve_auth(%{image: image}) when is_binary(image) do
    case Auth.resolve(image, nil) do
      nil -> :none
      auth -> {:auto, auth}
    end
  end

  defp resolve_auth(_), do: :none

  defp copy_to_container(id, config, conn) do
    Enum.reduce(config.copy_to, :ok, fn
      copy_to, :ok -> CopyTo.copy_to(conn, id, copy_to)
      _, error -> error
    end)
  end

  defp wait_for_container(container, wait_strategies, conn) do
    Enum.reduce(wait_strategies, :ok, fn
      strategy, :ok -> WaitStrategy.wait_until_container_is_ready(strategy, container, conn)
      _, error -> error
    end)
  end
end
