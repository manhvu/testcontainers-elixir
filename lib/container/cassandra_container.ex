# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.CassandraContainer do
  @moduledoc """
  Provides functionality for creating and managing Cassandra container configurations.
  """

  alias TestcontainerEx.CassandraContainer
  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config

  use TestcontainerEx.ContainerConfig

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
    :name,
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

  @doc """
  Sets the container name.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = config, name) when is_binary(name) do
    %__MODULE__{config | name: name}
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
      |> then(fn cfg ->
        if config.name, do: Config.with_name(cfg, config.name), else: cfg
      end)
      |> Config.valid_image!()
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end
end
