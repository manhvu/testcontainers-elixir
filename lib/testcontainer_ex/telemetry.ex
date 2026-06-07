defmodule TestcontainerEx.Telemetry do
  @moduledoc """
  Telemetry integration for TestcontainerEx.

  Emits structured events at key lifecycle points so users can hook into
  monitoring, metrics, or logging via `:telemetry`.

  ## Events

  | Event                                  | Measurements        | Metadata                  |
  |----------------------------------------|---------------------|---------------------------|
  | `[:testcontainer_ex, :container, :start]`  | `duration`, `monotonic_time` | `container_id`, `image`  |
  | `[:testcontainer_ex, :container, :stop]`   | `duration`, `monotonic_time` | `container_id`           |
  | `[:testcontainer_ex, :image, :pull]`       | `duration`, `monotonic_time` | `image`                  |
  | `[:testcontainer_ex, :network, :create]`   | `duration`, `monotonic_time` | `network_name`           |
  | `[:testcontainer_ex, :network, :remove]`   | `duration`, `monotonic_time` | `network_name`           |
  | `[:testcontainer_ex, :ryuk, :start]`       | `duration`, `monotonic_time` | `session_id`             |
  | `[:testcontainer_ex, :wait, :strategy]`    | `duration`, `monotonic_time` | `strategy`, `container_id` |

  ## Usage

  Attach a handler to measure container start times:

      :telemetry.attach(
        "my-handler",
        [:testcontainer_ex, :container, :start],
        fn _name, measurements, _meta, _config ->
          :io.format("Container started in ~p us~n", [measurements[:duration]])
        end,
        nil
      )

  ## With `telemetry_metrics`

      Metrics.summary("testcontainer_ex.container.start.duration",
        unit: {:microsecond, :millisecond}
      )
  """

  @doc """
  Executes the given function and emits a telemetry event with timing.

  Returns the result of `fun.` on success, or re-raises on error (still
  emitting the event with `error: true` in metadata).

  ## Parameters

    * `event_name` — list of atoms, e.g. `[:testcontainer_ex, :container, :start]`
    * `metadata` — map of extra metadata to include
    * `fun` — zero-arity function to time

  ## Examples

      with_telemetry(
        [:testcontainer_ex, :container, :start],
        %{image: "redis:7"},
        fn -> Lifecycle.start_container(builder, conn, state) end
      )
  """
  @spec with_telemetry([atom()], map(), (-> result)) :: result when result: var
  def with_telemetry(event_name, metadata, fun) when is_list(event_name) and is_map(metadata) do
    start_time = System.monotonic_time()
    start_meta = Map.put(metadata, :telemetry_span_start, true)

    :telemetry.execute(event_name ++ [:start], %{system_time: System.system_time()}, start_meta)

    try do
      result = fun.()

      duration = System.monotonic_time() - start_time
      measurements = %{duration: duration, monotonic_time: System.monotonic_time()}
      end_meta = metadata

      :telemetry.execute(event_name ++ [:stop], measurements, end_meta)
      :telemetry.execute(event_name, measurements, end_meta)

      result
    rescue
      exception ->
        duration = System.monotonic_time() - start_time
        measurements = %{duration: duration, monotonic_time: System.monotonic_time()}
        end_meta = Map.merge(metadata, %{error: true, exception: exception})

        :telemetry.execute(event_name ++ [:exception], measurements, end_meta)
        :telemetry.execute(event_name, measurements, end_meta)

        reraise exception, __STACKTRACE__
    end
  end

  @doc """
  Emits a telemetry event without timing a function.

  Useful for instantaneous events like "container stopped".
  """
  @spec event([atom()], map(), map()) :: :ok
  def event(event_name, measurements \\ %{}, metadata \\ %{})
      when is_list(event_name) and is_map(measurements) and is_map(metadata) do
    :telemetry.execute(event_name, measurements, metadata)
    :ok
  end

  @doc """
  Returns the list of all event names this module can emit.
  Useful for documentation or for attaching handlers programmatically.
  """
  @spec events() :: [[atom()]]
  def events do
    base = :testcontainer_ex

    for domain <- [:container, :image, :network, :ryuk, :wait],
        action <- [:start, :stop, :create, :remove, :pull, :strategy],
        suffix <- [[], [:start], [:stop], [:exception]] do
      [base, domain, action] ++ suffix
    end
    |> Enum.uniq()
  end
end
