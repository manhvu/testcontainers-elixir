defmodule TestcontainerEx.GenericContainerTest do
  use ExUnit.Case, async: true

  require Logger

  import TestcontainerEx.Container, only: [is_os: 1]
  import TestHelper, only: [port_open?: 2]

  test "can start and stop generic container" do
    config = %TestcontainerEx.Container{image: "redis:latest"}
    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end

  # This doesnt work on rootless docker, because binding ports to host requires root (i guess)
  # run test with --exclude needs_root if you are running rootless
  @tag :needs_root
  @tag :dood_limitation
  test "can start and stop generic container with network mode set to host" do
    if is_os(:linux) do
      config = %TestcontainerEx.Container{image: "redis:latest", network_mode: "host"}
      assert {:ok, container} = TestcontainerEx.start_container(config)
      Process.sleep(5000)
      assert :ok = port_open?("127.0.0.1", 6379)
      assert :ok = TestcontainerEx.stop_container(container.container_id)
    else
      Logger.warning("Host is not Linux, therefore not running network_mode test")
    end
  end
end
