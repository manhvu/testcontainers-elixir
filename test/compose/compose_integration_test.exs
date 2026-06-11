defmodule TestcontainerEx.Compose.ComposeIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :needs_dock
  @moduletag :integration

  alias TestcontainerEx.DockerCompose

  @fixtures_path Path.expand("../fixtures", __DIR__)

  describe "full compose lifecycle" do
    test "starts and stops a compose environment with redis" do
      compose = DockerCompose.new(@fixtures_path)

      assert :ok = TestcontainerEx.start_compose(compose)

      # Give services a moment to start
      Process.sleep(2_000)

      # Verify redis is running by checking docker compose ps
      {:ok, services} = TestcontainerEx.Compose.Cli.ps(compose)

      redis_service =
        Enum.find(services, fn s ->
          Map.get(s, "Service") == "redis" or Map.get(s, "Name") =~ "redis"
        end)

      assert redis_service != nil, "Expected redis service to be running"
      assert Map.get(redis_service, "State") =~ "running"

      # Get port mapping
      publishers = Map.get(redis_service, "Publishers", [])
      port = TestcontainerEx.Compose.Cli.parse_publishers(publishers) |> List.first()
      assert port != nil, "Expected port mapping for redis"
      {container_port, host_port} = port
      assert container_port == 6379
      assert host_port > 0

      # Verify connectivity to redis
      {:ok, conn} = :gen_tcp.connect(~c"127.0.0.1", host_port, [:binary, active: false], 5000)
      :gen_tcp.send(conn, "PING\r\n")
      {:ok, response} = :gen_tcp.recv(conn, 0, 5000)
      assert response =~ "PONG"
      :gen_tcp.close(conn)

      # Stop the compose environment
      assert :ok = TestcontainerEx.stop_compose(%{compose: compose})
    end
  end
end
