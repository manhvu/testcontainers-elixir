defmodule TestcontainerEx.Container.Behaviour do
  @moduledoc """
  Behaviour for defining custom container configurations.

  Implementing this behaviour provides a clear contract for custom container
  types, ensuring they expose the required callbacks.

  ## Example

      defmodule MyApp.RedisTestContainer do
        @behaviour TestcontainerEx.Container.Behaviour

        @impl true
        def new(opts \\\\ []) do
          TestcontainerEx.Container.new(Keyword.get(opts, :image, "redis:7-alpine"))
          |> TestcontainerEx.Container.with_exposed_port(6379)
          |> TestcontainerEx.Container.with_waiting_strategies(default_wait_strategies())
        end

        @impl true
        def default_wait_strategies do
          [TestcontainerEx.Wait.port("localhost", 6379, 30_000)]
        end

        @impl true
        def connection_opts(container) do
          [host: TestcontainerEx.Container.Info.host(container), port: TestcontainerEx.get_port(container, 6379)]
        end
      end
  """

  alias TestcontainerEx.Container.Config

  @doc "Return a default container configuration, optionally overridden by `opts`."
  @callback new(opts :: keyword()) :: Config.t()

  @doc "Return the default list of wait strategies for this container type."
  @callback default_wait_strategies() :: [struct()]

  @doc "Return keyword connection options for the running container."
  @callback connection_opts(container :: Config.t()) :: keyword()
end
