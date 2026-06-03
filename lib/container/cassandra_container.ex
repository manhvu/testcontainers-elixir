# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.CassandraContainer do
  @moduledoc """
  Provides functionality for creating and managing Cassandra container configurations.
  """

  alias TestcontainerEx.CassandraContainer
  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config

  import TestcontainerEx.Container.Config, only: [is_valid_image: 1]

  @default_image "cassandra"
  @default_tag "3.11.2"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_username "cassandra"
  @default_password "cassandra"
  @default_port 9042
  @default_wait_timeout 60_000

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :wait_timeout]
  defstruct [
    :image,
    :wait_timeout,
    check_image: @default_image,
    reuse: false
  ]

  def new,
    do: %__MODULE__{
      image: @default_image_with_tag,
      wait_timeout: @default_wait_timeout
    }

  def with_image(%__MODULE__{} = config, image) when is_binary(image) do
    %{config | image: image}
  end

  def with_check_image(%__MODULE__{} = config, check_image) when is_valid_image(check_image) do
    %__MODULE__{config | check_image: check_image}
  end

  def with_reuse(%__MODULE__{} = config, reuse) when is_boolean(reuse) do
    %__MODULE__{config | reuse: reuse}
  end

  def default_image, do: @default_image
  def default_port, do: @default_port
  def get_username, do: @default_username
  def get_password, do: @default_password

  def port(%Config{} = container), do: TestcontainerEx.get_port(container, @default_port)

  def connection_uri(%Config{} = container) do
    "#{TestcontainerEx.get_host(container)}:#{port(container)}"
  end

  defimpl Builder do
    @impl true
    @spec build(CassandraContainer.t()) :: Config.t()
    def build(%CassandraContainer{} = config) do
      Config.new(config.image)
      |> Config.with_exposed_port(CassandraContainer.default_port())
      |> Config.with_environment(:CASSANDRA_SNITCH, "GossipingPropertyFileSnitch")
      |> Config.with_environment(
        :JVM_OPTS,
        "-Dcassandra.skip_wait_for_gossip_to_settle=0 -Dcassandra.initial_token=0"
      )
      |> Config.with_environment(:HEAP_NEWSIZE, "128M")
      |> Config.with_environment(:MAX_HEAP_SIZE, "1024M")
      |> Config.with_environment(:CASSANDRA_ENDPOINT_SNITCH, "GossipingPropertyFileSnitch")
      |> Config.with_environment(:CASSANDRA_DC, "datacenter1")
      |> Config.with_waiting_strategy(
        CommandWaitStrategy.new(
          ["cqlsh", "-e", "describe keyspaces"],
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
