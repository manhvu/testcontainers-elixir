defmodule TestcontainerEx.GenericContainerTest do
  use ExUnit.Case, async: true

  require Logger

  import TestcontainerEx.Container.Config, only: [is_os: 1]
  import TestHelper, only: [port_open?: 2]

  @tag :needs_dock
  test "can start and stop generic container" do
    config = %TestcontainerEx.Container.Config{image: "redis:latest"}
    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert {:ok, :stopped} = TestcontainerEx.stop_container(container.container_id)
  end

  @tag :needs_dock
  @tag :needs_root
  @tag :dood_limitation
  test "can start and stop generic container with network mode set to host" do
    if is_os(:linux) do
      config = %TestcontainerEx.Container.Config{image: "redis:latest", network_mode: "host"}
      assert {:ok, container} = TestcontainerEx.start_container(config)
      Process.sleep(5000)
      assert :ok = port_open?("127.0.0.1", 6379)
      assert {:ok, :stopped} = TestcontainerEx.stop_container(container.container_id)
    else
      Logger.warning("Host is not Linux, therefore not running network_mode test")
    end
  end
end
