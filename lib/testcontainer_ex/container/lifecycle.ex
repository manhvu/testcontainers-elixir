defmodule TestcontainerEx.Container.Lifecycle do
  @moduledoc """
  Orchestrates container lifecycle: create, start, wait, pull, copy.

  This module is the bridge between the GenServer state and the Docker API.
  All functions require a connection and return `{:ok, container}` or `{:error, reason}`.
  """

  require Logger

  alias TestcontainerEx.{
    Container.Builder,
    Container.BuilderHelper,
    Container.Config,
    CopyTo,
    Engine.Api,
    Engine.Auth,
    Error,
    LogConsumer,
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
  @spec start_container(struct(), Req.Request.t(), map()) ::
          {:ok, Config.t()} | {:error, Error.t()}
  def start_container(builder, conn, state) do
    request_id = extract_request_id(builder) || generate_request_id()

    Logger.metadata(request_id: request_id, image: extract_image(builder))

    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :start],
      %{image: extract_image(builder), request_id: request_id},
      fn -> do_start_container(builder, conn, state) end
    )
  end

  defp extract_image(%{image: image}) when is_binary(image), do: image
  defp extract_image(%{config: %{image: image}}) when is_binary(image), do: image
  defp extract_image(_), do: "unknown"

  defp extract_request_id(%Config{request_id: id}) when is_binary(id), do: id
  defp extract_request_id(%{request_id: id}) when is_binary(id), do: id
  defp extract_request_id(%{config: %{request_id: id}}) when is_binary(id), do: id
  defp extract_request_id(_), do: nil

  defp generate_request_id do
    :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
  end

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
  Creates and starts multiple containers.

  Returns `{:ok, containers}` when every container starts. If one or more
  containers fail, returns `{:error, results}` where `results` keeps the input
  order and contains either `{:ok, container}` or `{:error, reason}`.
  """
  @spec start_containers([struct()], Req.Request.t(), map()) ::
          {:ok, [Config.t()]} | {:error, [term()]}
  def start_containers(builders, conn, state) when is_list(builders) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :batch_start],
      %{count: length(builders)},
      fn -> do_start_containers(builders, conn, state, []) end
    )
  end

  @doc """
  Stops a container by ID.

  Returns `{:ok, :stopped}` on success, `{:ok, :already_stopped}` if the
  container is not running, or `{:error, TestcontainerEx.Error.t()}` on failure.
  """
  @spec stop_container(String.t(), Req.Request.t()) ::
          {:ok, :stopped} | {:ok, :already_stopped} | {:error, Error.t()}
  def stop_container(container_id, conn) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :stop],
      %{container_id: container_id},
      fn ->
        case Api.stop_container(container_id, conn) do
          :ok ->
            {:ok, :stopped}

          {:error, :not_found} ->
            {:ok, :already_stopped}

          {:error, reason} ->
            {:error, Error.docker_api_error("Failed to stop container #{container_id}", reason)}
        end
      end
    )
  end

  @doc """
  Stops multiple containers.
  """
  @spec stop_containers([String.t()], Req.Request.t()) :: {:ok, [term()]} | {:error, [term()]}
  def stop_containers(container_ids, conn) when is_list(container_ids) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :batch_stop],
      %{count: length(container_ids)},
      fn -> do_stop_containers(container_ids, conn, []) end
    )
  end

  @doc """
  Inspects a container by ID.
  """
  @spec inspect_container(String.t(), Req.Request.t()) :: {:ok, Config.t()} | {:error, term()}
  def inspect_container(container_id, conn) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :inspect],
      %{container_id: container_id},
      fn -> Api.get_container(container_id, conn) end
    )
  end

  @doc """
  Fetches container logs.
  """
  @spec container_logs(String.t(), Req.Request.t(), keyword()) ::
          {:ok, map()} | {:ok, reference() | pid()} | {:error, term()}
  def container_logs(container_id, conn, opts \\ []) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :logs],
      %{container_id: container_id, opts: opts},
      fn -> Api.logs(container_id, conn, opts) end
    )
  end

  @doc """
  Executes a command inside a container.
  """
  @spec exec(String.t(), [String.t()], Req.Request.t()) :: {:ok, String.t()} | {:error, term()}
  def exec(container_id, command, conn) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :exec],
      %{container_id: container_id, command: command},
      fn -> do_exec(container_id, command, conn) end
    )
  end

  @doc """
  Monitors a container until a predicate succeeds or the timeout elapses.
  """
  @spec monitor_container(
          String.t(),
          (Config.t() -> {:ok, term()} | {:error, term()}),
          Req.Request.t(),
          keyword()
        ) ::
          {:ok, term()} | {:error, term()}
  def monitor_container(container_id, predicate, conn, opts \\ []) do
    Telemetry.with_telemetry(
      [:testcontainer_ex, :container, :monitor],
      %{container_id: container_id},
      fn -> do_monitor_container(container_id, predicate, conn, opts) end
    )
  end

  # ── Private ───────────────────────────────────────────────────────

  defp create_and_start(config, builder, conn, state) do
    config = resolve_pull_policy(config, state.properties)

    with :ok <- maybe_pull_image(config, conn),
         {:ok, id} <- create_container_with_retry(config, conn),
         :ok <- copy_to_container(id, config, conn) do
      start_and_wait(id, config, builder, conn)
    else
      {:error, reason} -> {:error, Error.wrap(reason)}
    end
  end

  defp do_start_containers([], _conn, _state, acc) do
    acc
    |> Enum.reverse()
    |> finalize_batch_result()
  end

  defp do_start_containers([builder | rest], conn, state, acc) do
    result = start_container(builder, conn, state)
    do_start_containers(rest, conn, state, [result | acc])
  end

  defp do_stop_containers([], _conn, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp do_stop_containers([container_id | rest], conn, acc) do
    do_stop_containers(rest, conn, [stop_container(container_id, conn) | acc])
  end

  defp finalize_batch_result(results) do
    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, container} -> container end)}
    else
      {:error, results}
    end
  end

  defp do_exec(container_id, command, conn) do
    with {:ok, exec_id} <- Api.start_exec(container_id, command, conn),
         {:ok, status} <- wait_for_exec(exec_id, conn, 10_000, 100) do
      {:ok, %{exec_id: exec_id, exit_code: status.exit_code}}
    end
  end

  defp wait_for_exec(exec_id, conn, timeout, retry_delay) do
    started_at = System.monotonic_time(:millisecond)
    do_wait_for_exec(exec_id, conn, timeout, retry_delay, started_at)
  end

  defp do_wait_for_exec(exec_id, conn, timeout, retry_delay, started_at) do
    if System.monotonic_time(:millisecond) - started_at > timeout do
      {:error, {:exec_timeout, timeout}}
    else
      case Api.inspect_exec(exec_id, conn) do
        {:ok, %{running: true}} ->
          Process.sleep(retry_delay)
          do_wait_for_exec(exec_id, conn, timeout, retry_delay, started_at)

        {:ok, status} ->
          {:ok, status}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_monitor_container(container_id, predicate, conn, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    retry_delay = Keyword.get(opts, :retry_delay, 250)
    started_at = System.monotonic_time(:millisecond)
    do_monitor_container(container_id, predicate, conn, timeout, retry_delay, started_at)
  end

  defp do_monitor_container(container_id, predicate, conn, timeout, retry_delay, started_at) do
    with {:ok, container} <- Api.get_container(container_id, conn) do
      case safe_predicate(predicate, container) do
        {:ok, value} ->
          {:ok, value}

        {:error, reason} ->
          if System.monotonic_time(:millisecond) - started_at > timeout do
            {:error, {:monitor_timeout, reason, timeout}}
          else
            Process.sleep(retry_delay)
            do_monitor_container(container_id, predicate, conn, timeout, retry_delay, started_at)
          end
      end
    end
  end

  defp safe_predicate(predicate, container) do
    predicate.(container)
  rescue
    exception ->
      {:error, {exception.__struct__, Exception.message(exception), __STACKTRACE__}}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end

  # Retry container creation up to 3 times on transient errors.
  # The Docker daemon may return :econnrefused or HTTP 500 during startup
  # or when under resource pressure.
  defp create_container_with_retry(config, conn, retries_left \\ 2)

  defp create_container_with_retry(config, conn, 0) do
    Api.create_container(config, conn)
  end

  defp create_container_with_retry(config, conn, retries_left) do
    case Api.create_container(config, conn) do
      {:error, :econnrefused} ->
        Logger.debug("Container creation got econnrefused, retrying in 500ms...")
        :timer.sleep(500)
        create_container_with_retry(config, conn, retries_left - 1)

      {:error, {:http_error, 500}} ->
        Logger.debug("Container creation got HTTP 500, retrying in 1000ms...")
        :timer.sleep(1000)
        create_container_with_retry(config, conn, retries_left - 1)

      other ->
        other
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

  # Retry the full start sequence on transient Docker daemon errors.
  # Covers: HTTP 500 from create/start, econnrefused during start,
  # and wait strategy failures from daemon hiccups.
  defp start_and_wait(id, config, builder, conn, retries_left \\ 2)

  defp start_and_wait(id, config, builder, conn, 0) do
    do_start_and_wait(id, config, builder, conn)
  end

  defp start_and_wait(id, config, builder, conn, retries_left) do
    case do_start_and_wait(id, config, builder, conn) do
      {:error, %Error{code: :docker_api_error, cause: {:http_error, 500}}} ->
        Logger.warning(
          "Container start got HTTP 500, retrying in 2000ms, #{retries_left} retries left"
        )

        :timer.sleep(2000)
        start_and_wait(id, config, builder, conn, retries_left - 1)

      {:error, %Error{code: :docker_api_error, cause: :econnrefused}} ->
        Logger.warning(
          "Container start got econnrefused, retrying in 1000ms, #{retries_left} retries left"
        )

        :timer.sleep(1000)
        start_and_wait(id, config, builder, conn, retries_left - 1)

      other ->
        other
    end
  end

  defp do_start_and_wait(id, config, builder, conn) do
    with :ok <- start_container_with_retry(id, conn),
         {:ok, container} <- Api.get_container(id, conn),
         :ok <- Builder.after_start(builder, container, conn),
         :ok <- wait_for_container(container, config.wait_strategies, conn) do
      maybe_start_log_consumer(container, conn, config)
      {:ok, container}
    else
      {:error, reason} ->
        Logger.info("Cleaning up container #{id} after failed start")
        Api.stop_container(id, conn)
        {:error, Error.wrap(reason)}
    end
  end

  defp maybe_start_log_consumer(%Config{} = _container, _conn, %Config{log_consumer: nil}) do
    :ok
  end

  defp maybe_start_log_consumer(%Config{container_id: id}, conn, %Config{log_consumer: level})
       when is_binary(id) and is_atom(level) do
    case LogConsumer.start_link(id, conn, level) do
      {:ok, _pid} -> :ok
    end
  end

  defp maybe_start_log_consumer(_, _, _), do: :ok

  # Retry container start up to 3 times on transient errors.
  defp start_container_with_retry(id, conn, retries_left \\ 2)

  defp start_container_with_retry(id, conn, 0) do
    Api.start_container(id, conn)
  end

  defp start_container_with_retry(id, conn, retries_left) do
    case Api.start_container(id, conn) do
      {:error, :econnrefused} ->
        Logger.debug("Container start got econnrefused, retrying in 500ms...")
        :timer.sleep(500)
        start_container_with_retry(id, conn, retries_left - 1)

      {:error, {:http_error, 500}} ->
        Logger.debug("Container start got HTTP 500, retrying in 1000ms...")
        :timer.sleep(1000)
        start_container_with_retry(id, conn, retries_left - 1)

      other ->
        other
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

  # Retry image pull up to 3 times on transient HTTP 500 errors from the daemon.
  defp pull_with_fallback(config, conn, retries_left \\ 3)

  defp pull_with_fallback(config, conn, 0) do
    do_pull_with_fallback(config, conn)
  end

  defp pull_with_fallback(config, conn, retries_left) do
    case do_pull_with_fallback(config, conn) do
      {:error, {:http_error, 500}} ->
        Logger.warning(
          "Image pull got HTTP 500, retrying in 2000ms, #{retries_left} retries left"
        )

        :timer.sleep(2000)
        pull_with_fallback(config, conn, retries_left - 1)

      other ->
        other
    end
  end

  defp do_pull_with_fallback(config, conn) do
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
    Enum.reduce_while(config.copy_to, :ok, fn copy_to, :ok ->
      case CopyTo.copy_to(conn, id, copy_to) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp wait_for_container(container, wait_strategies, conn) do
    Enum.reduce(wait_strategies, :ok, fn
      strategy, :ok -> WaitStrategy.wait_until_container_is_ready(strategy, container, conn)
      _, error -> error
    end)
  end
end
