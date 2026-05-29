defmodule Test.NginxContainer do
  @moduledoc false
  defstruct []

  defimpl TestcontainerEx.ContainerBuilder do
    alias TestcontainerEx.CommandWaitStrategy
    alias TestcontainerEx.Docker
    import TestcontainerEx.Container

    @impl true
    def build(%Test.NginxContainer{}) do
      new("nginx:alpine")
      |> with_waiting_strategy(CommandWaitStrategy.new(["cat", "/tmp/foo.txt"]))
    end

    @impl true
    def after_start(_config, container, conn) do
      Docker.Api.put_file(container.container_id, conn, "/tmp", "foo.txt", "Hello foo bar")
    end
  end
end
