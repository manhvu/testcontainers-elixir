# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Container.ScyllaContainerTest do
  use ExUnit.Case, async: true

  import TestcontainerEx.ExUnit

  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.ScyllaContainer

  describe "new/0" do
    test "creates a ScyllaContainer with default configuration" do
      config = ScyllaContainer.new()

      assert config.image == "scylladb/scylla:latest"
      assert config.wait_timeout == 120_000
      assert config.check_image == "scylladb/scylla"
      assert config.reuse == false
    end
  end

  describe "with_image/2" do
    test "overrides the default image" do
      config = ScyllaContainer.new()
      new_config = ScyllaContainer.with_image(config, "scylladb/scylla:5.4")

      assert new_config.image == "scylladb/scylla:5.4"
    end

    test "raises if image is not a binary" do
      config = ScyllaContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ScyllaContainer, :with_image, [config, 123])
      end
    end
  end

  describe "with_wait_timeout/2" do
    test "overrides the default wait timeout" do
      config = ScyllaContainer.new()
      new_config = ScyllaContainer.with_wait_timeout(config, 300_000)

      assert new_config.wait_timeout == 300_000
    end

    test "raises if timeout is not a positive integer" do
      config = ScyllaContainer.new()

      assert_raise FunctionClauseError, fn ->
        ScyllaContainer.with_wait_timeout(config, -1)
      end

      assert_raise FunctionClauseError, fn ->
        apply(ScyllaContainer, :with_wait_timeout, [config, "120000"])
      end
    end
  end

  describe "with_check_image/2" do
    test "accepts a string check image" do
      config = ScyllaContainer.new()
      new_config = ScyllaContainer.with_check_image(config, "scylla")

      assert new_config.check_image == "scylla"
    end

    test "accepts a regex check image" do
      config = ScyllaContainer.new()
      new_config = ScyllaContainer.with_check_image(config, ~r/scylla.*/)

      assert Regex.source(new_config.check_image) == "scylla.*"
    end
  end

  describe "with_reuse/2" do
    test "sets reuse to true" do
      config = ScyllaContainer.new()
      new_config = ScyllaContainer.with_reuse(config, true)

      assert new_config.reuse == true
    end

    test "sets reuse to false" do
      config =
        ScyllaContainer.new()
        |> ScyllaContainer.with_reuse(true)
        |> ScyllaContainer.with_reuse(false)

      assert config.reuse == false
    end

    test "raises if reuse is not a boolean" do
      config = ScyllaContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ScyllaContainer, :with_reuse, [config, "true"])
      end
    end
  end

  describe "default_image/0" do
    test "returns the default image name" do
      assert ScyllaContainer.default_image() == "scylladb/scylla"
    end
  end

  describe "default_port/0" do
    test "returns the default CQL port" do
      assert ScyllaContainer.default_port() == 9042
    end
  end

  describe "Builder.build/1" do
    test "builds a Config with correct image" do
      config =
        ScyllaContainer.new()
        |> Builder.build()

      assert config.image == "scylladb/scylla:latest"
    end

    test "builds a Config with CQL port exposed" do
      config =
        ScyllaContainer.new()
        |> Builder.build()

      assert {9042, nil} in config.exposed_ports
    end

    test "builds a Config with --smp 1 --memory 1G command" do
      config =
        ScyllaContainer.new()
        |> Builder.build()

      assert config.cmd == ["--smp", "1", "--memory", "1G"]
    end

    test "builds a Config with SCYLLA_SKIP_WAIT_FOR_GOSPEL_TO_SETTLE env" do
      config =
        ScyllaContainer.new()
        |> Builder.build()

      assert config.environment[:SCYLLA_SKIP_WAIT_FOR_GOSPEL_TO_SETTLE] == "0"
    end

    test "builds a Config with nodetool status wait strategy" do
      config =
        ScyllaContainer.new()
        |> Builder.build()

      assert [%CommandWaitStrategy{command: ["nodetool", "status"]}] = config.wait_strategies
    end

    test "builds a Config with custom image" do
      config =
        ScyllaContainer.new()
        |> ScyllaContainer.with_image("scylladb/scylla:5.4")
        |> Builder.build()

      assert config.image == "scylladb/scylla:5.4"
    end

    test "builds a Config with custom wait timeout" do
      config =
        ScyllaContainer.new()
        |> ScyllaContainer.with_wait_timeout(300_000)
        |> Builder.build()

      [%CommandWaitStrategy{timeout: timeout}] = config.wait_strategies
      assert timeout == 300_000
    end

    test "builds a Config with reuse enabled" do
      config =
        ScyllaContainer.new()
        |> ScyllaContainer.with_reuse(true)
        |> Builder.build()

      assert config.reuse == true
    end

    test "builds a Config with check_image set" do
      config =
        ScyllaContainer.new()
        |> ScyllaContainer.with_check_image("scylla")
        |> Builder.build()

      assert Regex.source(config.check_image) == "scylla"
    end
  end

  describe "port/1" do
    test "returns the mapped port from a container" do
      container = %Config{
        container_id: "abc123",
        image: "scylladb/scylla:latest",
        exposed_ports: [{9042, 19042}]
      }

      assert ScyllaContainer.port(container) == 19042
    end

    test "returns nil when port is not mapped" do
      container = %Config{
        container_id: "abc123",
        image: "scylladb/scylla:latest",
        exposed_ports: []
      }

      assert ScyllaContainer.port(container) == nil
    end
  end

  describe "connection_uri/1" do
    test "returns host:port string" do
      container = %Config{
        container_id: "abc123",
        image: "scylladb/scylla:latest",
        exposed_ports: [{9042, 19042}]
      }

      uri = ScyllaContainer.connection_uri(container)
      assert uri =~ ":#{19042}"
    end
  end

  describe "runtime behavior" do
    @moduletag :needs_dock
    container(:scylla, ScyllaContainer.new())

    test "provides a ready-to-use scylla container", %{scylla: scylla} do
      assert scylla.container_id != nil
      assert ScyllaContainer.port(scylla) != nil
    end

    test "is reachable via CQL", %{scylla: scylla} do
      host = TestcontainerEx.get_host(scylla)
      port = ScyllaContainer.port(scylla)

      # Give Scylla a moment to fully accept CQL connections after nodetool status passes
      Process.sleep(1000)

      {:ok, conn} = Xandra.start_link(nodes: ["#{host}:#{port}"])

      {:ok, result} = Xandra.execute(conn, "SELECT now() FROM system.local")
      assert length(result.rows) == 1
    end

    test "can create keyspace and table", %{scylla: scylla} do
      host = TestcontainerEx.get_host(scylla)
      port = ScyllaContainer.port(scylla)

      # Give Scylla a moment to fully accept CQL connections after nodetool status passes
      Process.sleep(1000)

      {:ok, conn} = Xandra.start_link(nodes: ["#{host}:#{port}"])

      {:ok, _} =
        Xandra.execute(
          conn,
          "CREATE KEYSPACE IF NOT EXISTS test_ks WITH replication = {'class':'SimpleStrategy', 'replication_factor': 1}"
        )

      {:ok, _} =
        Xandra.execute(
          conn,
          "CREATE TABLE IF NOT EXISTS test_ks.users (id int PRIMARY KEY, name text)"
        )

      {:ok, _} =
        Xandra.execute(conn, "INSERT INTO test_ks.users (id, name) VALUES (1, 'Test User')")

      {:ok, result} = Xandra.execute(conn, "SELECT name FROM test_ks.users WHERE id = 1")
      [%{"name" => name}] = result.rows
      assert name == "Test User"
    end
  end
end
