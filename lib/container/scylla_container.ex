# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.ScyllaContainer do
  @moduledoc """
  Provides functionality for creating and managing ScyllaDB container configurations.

  ScyllaDB is a Cassandra-compatible NoSQL database. This container exposes
  port 9042 (CQL) by default and uses `nodetool` to wait for readiness.

  ## Example

      {:ok, container} = TestcontainerEx.start_container(ScyllaContainer.new())
      port = ScyllaContainer.port(container)
      host = TestcontainerEx.get_host(container)
  """

  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.ScyllaContainer

  import TestcontainerEx.Container.Config, only: [is_valid_image: 1]

  @default_image "scylladb/scylla"
  @default_tag "latest"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_cql_port 9042
  @default_wait_timeout 120_000

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :wait_timeout]
  defstruct [
    :image,
    :wait_timeout,
    check_image: @default_image,
    reuse: false
  ]

  # ── Constructor ────────────────────────────────────────────────────

  @doc """
  Creates a new ScyllaContainer with default configuration.
  """
  @spec new() :: t()
  def new,
    do: %__MODULE__{
      image: @default_image_with_tag,
      wait_timeout: @default_wait_timeout
    }

  # ── Setters ────────────────────────────────────────────────────────

  @doc """
  Sets the container image (e.g. `"scylladb/scylla:5.4"`).
  """
  @spec with_image(t(), String.t()) :: t()
  def with_image(%__MODULE__{} = config, image) when is_binary(image) do
    %{config | image: image}
  end

  @doc """
  Sets the wait timeout in milliseconds.
  """
  @spec with_wait_timeout(t(), pos_integer()) :: t()
  def with_wait_timeout(%__MODULE__{} = config, timeout)
      when is_integer(timeout) and timeout > 0 do
    %{config | wait_timeout: timeout}
  end

  @doc """
  Sets the check image regex used to validate the image name.
  """
  @spec with_check_image(t(), String.t() | Regex.t()) :: t()
  def with_check_image(%__MODULE__{} = config, check_image) when is_valid_image(check_image) do
    %__MODULE__{config | check_image: check_image}
  end

  @doc """
  Enables or disables container reuse.
  """
  @spec with_reuse(t(), boolean()) :: t()
  def with_reuse(%__MODULE__{} = config, reuse) when is_boolean(reuse) do
    %__MODULE__{config | reuse: reuse}
  end

  # ── Accessors ──────────────────────────────────────────────────────

  @doc """
  Returns the default image name without tag.
  """
  @spec default_image() :: String.t()
  def default_image, do: @default_image

  @doc """
  Returns the default CQL port (9042).
  """
  @spec default_port() :: 9042
  def default_port, do: @default_cql_port

  @doc """
  Returns the mapped host port for the CQL port.
  """
  @spec port(Config.t()) :: integer() | nil
  def port(%Config{} = container), do: TestcontainerEx.get_port(container, @default_cql_port)

  @doc """
  Returns a `host:port` connection URI string.
  """
  @spec connection_uri(Config.t()) :: String.t()
  def connection_uri(%Config{} = container) do
    "#{TestcontainerEx.get_host(container)}:#{port(container)}"
  end

  # ── Builder protocol ───────────────────────────────────────────────

  defimpl Builder do
    @impl true
    @spec build(ScyllaContainer.t()) :: Config.t()
    def build(%ScyllaContainer{} = config) do
      Config.new(config.image)
      |> Config.with_exposed_port(ScyllaContainer.default_port())
      |> Config.with_cmd(["--smp", "1", "--memory", "1G"])
      |> Config.with_environment(:SCYLLA_SKIP_WAIT_FOR_GOSPEL_TO_SETTLE, "0")
      |> Config.with_waiting_strategy(
        CommandWaitStrategy.new(
          ["nodetool", "status"],
          config.wait_timeout
        )
      )
      |> Config.with_check_image(config.check_image)
      |> Config.with_reuse(config.reuse)
      |> Config.valid_image!()
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end
end
