defmodule CopyToTest do
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.HttpWaitStrategy
  use ExUnit.Case, async: true

  @tag :needs_dock
  test "copy contents to target" do
    port = 80
    contents = "Hello there"

    config =
      %Config{image: "nginx:alpine"}
      |> Config.with_exposed_port(port)
      |> Config.with_waiting_strategy(HttpWaitStrategy.new("/hello.txt", port))
      |> Config.with_copy_to("/usr/share/nginx/html/hello.txt", contents)

    assert {:ok, container} = TestcontainerEx.start_container(config)

    host = TestcontainerEx.get_host(container)
    mapped_port = TestcontainerEx.get_port(container, port)
    {:ok, %{body: body}} = Req.get("http://#{host}:#{mapped_port}/hello.txt")

    assert contents == body
    assert {:ok, :stopped} = TestcontainerEx.stop_container(container.container_id)
  end
end
