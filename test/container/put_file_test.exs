defmodule TestcontainerEx.Container.PutFileTest do
  use ExUnit.Case, async: true

  import TestcontainerEx.ExUnit

  alias TestcontainerEx.Container.Config

  @tag :needs_dock
  test "upload file to container" do
    port = 80
    contents = "Hello there"

    config =
      %Config{image: "nginx:alpine"}
      |> Config.with_exposed_port(port)
      |> Config.with_copy_to("/usr/share/nginx/html/hello.txt", contents)

    assert {:ok, container} = TestcontainerEx.start_container(config)

    host = TestcontainerEx.get_host(container)
    mapped_port = TestcontainerEx.get_port(container, port)
    {:ok, %{body: body}} = Tesla.get("http://#{host}:#{mapped_port}/hello.txt")

    assert contents == body
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end
end
