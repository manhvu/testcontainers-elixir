defmodule CopyToTest do
  alias TestcontainerEx.HttpWaitStrategy
  use ExUnit.Case, async: true

  test "copy contents to target" do
    port = 80
    contents = "Hello there"

    config =
      %TestcontainerEx.Container{image: "nginx:alpine"}
      |> TestcontainerEx.Container.with_exposed_port(port)
      |> TestcontainerEx.Container.with_waiting_strategy(HttpWaitStrategy.new("/hello.txt", port))
      |> TestcontainerEx.Container.with_copy_to("/usr/share/nginx/html/hello.txt", contents)

    assert {:ok, container} = TestcontainerEx.start_container(config)

    host = TestcontainerEx.get_host(container)
    mapped_port = TestcontainerEx.get_port(container, port)
    {:ok, %{body: body}} = Tesla.get("http://#{host}:#{mapped_port}/hello.txt")

    assert contents == body
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end
end
