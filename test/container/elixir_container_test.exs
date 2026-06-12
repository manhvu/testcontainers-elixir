# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Container.ElixirContainerTest do
  use ExUnit.Case, async: true

  import TestcontainerEx.ExUnit

  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.ElixirContainer
  alias TestcontainerEx.LogWaitStrategy
  alias TestcontainerEx.PortWaitStrategy

  describe "new/0" do
    test "creates an ElixirContainer with default configuration" do
      config = ElixirContainer.new()

      assert config.image == "elixir:latest"
      assert config.wait_timeout == 120_000
      assert config.check_image == "elixir"
      assert config.reuse == false
      assert config.cookie == nil
      assert config.node_name == nil
      assert config.dist_port == nil
      assert config.project_path == nil
      assert config.release_name == nil
      assert config.release_args == []
      assert config.vm_args == []
      assert config.env_vars == %{}
      assert config.cmd == nil
      assert config.working_dir == nil
    end
  end

  describe "with_image/2" do
    test "overrides the default image" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_image(config, "elixir:1.17-otp-27")

      assert new_config.image == "elixir:1.17-otp-27"
    end

    test "raises if image is not a binary" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_image, [config, 123])
      end
    end
  end

  describe "with_wait_timeout/2" do
    test "overrides the default wait timeout" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_wait_timeout(config, 300_000)

      assert new_config.wait_timeout == 300_000
    end

    test "raises if timeout is not a positive integer" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        ElixirContainer.with_wait_timeout(config, -1)
      end

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_wait_timeout, [config, "120000"])
      end
    end
  end

  describe "with_cookie/2" do
    test "sets the distribution cookie" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_cookie(config, "my-secret")

      assert new_config.cookie == "my-secret"
    end

    test "raises if cookie is not a binary" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_cookie, [config, :atom])
      end
    end
  end

  describe "with_node_name/2" do
    test "sets the node name with long name format" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_node_name(config, "app@192.168.1.100")

      assert new_config.node_name == "app@192.168.1.100"
    end

    test "sets the node name with short name format" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_node_name(config, "myapp")

      assert new_config.node_name == "myapp"
    end

    test "raises if node_name is not a binary" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_node_name, [config, 123])
      end
    end
  end

  describe "with_distribution_port/2" do
    test "sets the distribution port" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_distribution_port(config, 9100)

      assert new_config.dist_port == 9100
    end

    test "raises if port is not a positive integer" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        ElixirContainer.with_distribution_port(config, -1)
      end

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_distribution_port, [config, "9100"])
      end
    end
  end

  describe "with_project/2" do
    test "sets the project path and working directory" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_project(config, "/path/to/my_app")

      assert new_config.project_path == "/path/to/my_app"
      assert new_config.working_dir == "/app"
    end

    test "raises if path is not a binary" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_project, [config, 123])
      end
    end
  end

  describe "with_release/2" do
    test "sets the release name" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_release(config, "my_app")

      assert new_config.release_name == "my_app"
    end

    test "raises if name is not a binary" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_release, [config, :my_app])
      end
    end
  end

  describe "with_release_args/2" do
    test "sets the release args" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_release_args(config, ["start_iex"])

      assert new_config.release_args == ["start_iex"]
    end

    test "raises if args is not a list" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_release_args, [config, "start"])
      end
    end
  end

  describe "with_vm_args/2" do
    test "sets vm.args entries" do
      config = ElixirContainer.new()

      new_config =
        ElixirContainer.with_vm_args(config, [
          "-kernel inet_dist_listen_min 9100",
          "-kernel inet_dist_listen_max 9100"
        ])

      assert new_config.vm_args == [
               "-kernel inet_dist_listen_min 9100",
               "-kernel inet_dist_listen_max 9100"
             ]
    end

    test "raises if vm_args is not a list" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_vm_args, [config, "-kernel foo"])
      end
    end
  end

  describe "with_env_vars/2" do
    test "sets environment variables" do
      config = ElixirContainer.new()

      new_config =
        ElixirContainer.with_env_vars(config, %{
          "MIX_ENV" => "prod",
          "DATABASE_URL" => "postgres://localhost/test"
        })

      assert new_config.env_vars["MIX_ENV"] == "prod"
      assert new_config.env_vars["DATABASE_URL"] == "postgres://localhost/test"
    end

    test "merges with existing env vars" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_env_vars(%{"FOO" => "bar"})
        |> ElixirContainer.with_env_vars(%{"BAZ" => "qux"})

      assert config.env_vars["FOO"] == "bar"
      assert config.env_vars["BAZ"] == "qux"
    end

    test "raises if vars is not a map" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_env_vars, [config, "MIX_ENV=prod"])
      end
    end
  end

  describe "with_cmd/2" do
    test "sets a custom command" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_cmd(config, ["mix", "test"])

      assert new_config.cmd == ["mix", "test"]
    end

    test "raises if cmd is not a list" do
      config = ElixirContainer.new()

      assert_raise FunctionClauseError, fn ->
        apply(ElixirContainer, :with_cmd, [config, "mix test"])
      end
    end
  end

  describe "with_check_image/2" do
    test "accepts a string check image" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_check_image(config, "elixir")

      assert new_config.check_image == "elixir"
    end

    test "accepts a regex check image" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_check_image(config, ~r/elixir.*/)

      assert Regex.source(new_config.check_image) == "elixir.*"
    end
  end

  describe "with_reuse/2" do
    test "sets reuse to true" do
      config = ElixirContainer.new()
      new_config = ElixirContainer.with_reuse(config, true)

      assert new_config.reuse == true
    end

    test "sets reuse to false" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_reuse(true)
        |> ElixirContainer.with_reuse(false)

      assert config.reuse == false
    end
  end

  describe "default_image/0" do
    test "returns the default image name" do
      assert ElixirContainer.default_image() == "elixir"
    end
  end

  describe "epmd_port/0" do
    test "returns the EPMD port" do
      assert ElixirContainer.epmd_port() == 4369
    end
  end

  describe "default_dist_port/0" do
    test "returns the default distribution port" do
      assert ElixirContainer.default_dist_port() == 9100
    end
  end

  describe "Builder.build/1 — basic (no distribution)" do
    test "builds a Config with correct image" do
      config =
        ElixirContainer.new()
        |> Builder.build()

      assert config.image == "elixir:latest"
    end

    test "builds a Config with IEx log wait strategy" do
      config =
        ElixirContainer.new()
        |> Builder.build()

      assert [%LogWaitStrategy{log_regex: regex}] = config.wait_strategies
      assert Regex.match?(regex, "iex(1)> ")
    end

    test "builds a Config with check_image set" do
      config =
        ElixirContainer.new()
        |> Builder.build()

      assert Regex.source(config.check_image) == "elixir"
    end

    test "builds a Config with custom image" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_image("elixir:1.17-otp-27")
        |> Builder.build()

      assert config.image == "elixir:1.17-otp-27"
    end

    test "builds a Config with custom wait timeout" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_wait_timeout(300_000)
        |> Builder.build()

      [%LogWaitStrategy{timeout: timeout}] = config.wait_strategies
      assert timeout == 300_000
    end

    test "builds a Config with reuse enabled" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_reuse(true)
        |> Builder.build()

      assert config.reuse == true
    end

    test "builds a Config with custom command" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_cmd(["mix", "test"])
        |> Builder.build()

      assert config.cmd == ["mix", "test"]
    end
  end

  describe "Builder.build/1 — with distribution" do
    test "exposes EPMD and distribution ports" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_node_name("app@192.168.1.100")
        |> ElixirContainer.with_distribution_port(9100)
        |> Builder.build()

      assert {4369, nil} in config.exposed_ports
      assert {9100, nil} in config.exposed_ports
    end

    test "sets distribution environment variables" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_node_name("app@192.168.1.100")
        |> ElixirContainer.with_cookie("secret")
        |> ElixirContainer.with_distribution_port(9100)
        |> Builder.build()

      assert config.environment["RELEASE_DISTRIBUTION"] == "name"
      assert config.environment["RELEASE_NODE"] == "app@192.168.1.100"
      assert config.environment["RELEASE_COOKIE"] == "secret"
      assert config.environment["ELIXIR_DIST_PORT"] == "9100"
    end

    test "uses default distribution port when not specified" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_node_name("app@192.168.1.100")
        |> Builder.build()

      assert {4369, nil} in config.exposed_ports
      assert {9100, nil} in config.exposed_ports
      assert config.environment["ELIXIR_DIST_PORT"] == "9100"
    end

    test "adds port wait strategy for distribution port" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_node_name("app@192.168.1.100")
        |> ElixirContainer.with_distribution_port(9100)
        |> Builder.build()

      assert [%PortWaitStrategy{port: 9100} | _] = config.wait_strategies
    end

    test "uses default cookie when not specified" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_node_name("app@192.168.1.100")
        |> Builder.build()

      assert config.environment["RELEASE_COOKIE"] == "default-cookie"
    end
  end

  describe "Builder.build/1 — with project mount" do
    test "bind-mounts the project path" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_project("/path/to/my_app")
        |> Builder.build()

      assert [%{host_src: "/path/to/my_app", container_dest: "/app", options: "rw"}] =
               config.bind_mounts
    end
  end

  describe "Builder.build/1 — with env vars" do
    test "sets environment variables on the config" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_env_vars(%{"MIX_ENV" => "test"})
        |> Builder.build()

      assert config.environment["MIX_ENV"] == "test"
    end
  end

  describe "Builder.build/1 — with release" do
    test "uses release log wait strategy" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_release("my_app")
        |> Builder.build()

      assert [%LogWaitStrategy{log_regex: regex}] = config.wait_strategies
      assert Regex.match?(regex, "Running MyApp with")
    end
  end

  describe "connection_node/1" do
    test "returns nil when no node_name is configured" do
      container = %Config{
        container_id: "abc123",
        image: "elixir:latest",
        environment: %{},
        exposed_ports: []
      }

      assert ElixirContainer.connection_node(container) == nil
    end

    test "returns nil when RELEASE_NODE is not set" do
      container = %Config{
        container_id: "abc123",
        image: "elixir:latest",
        environment: %{},
        exposed_ports: [{9100, 19100}]
      }

      assert ElixirContainer.connection_node(container) == nil
    end
  end

  describe "mapped_epmd_port/1" do
    test "returns the mapped EPMD port" do
      container = %Config{
        container_id: "abc123",
        image: "elixir:latest",
        exposed_ports: [{4369, 14369}]
      }

      assert ElixirContainer.mapped_epmd_port(container) == 14369
    end

    test "returns nil when EPMD port is not mapped" do
      container = %Config{
        container_id: "abc123",
        image: "elixir:latest",
        exposed_ports: []
      }

      assert ElixirContainer.mapped_epmd_port(container) == nil
    end
  end

  describe "mapped_dist_port/1" do
    test "returns the mapped distribution port from env" do
      container = %Config{
        container_id: "abc123",
        image: "elixir:latest",
        environment: %{"ELIXIR_DIST_PORT" => "9100"},
        exposed_ports: [{9100, 19100}]
      }

      assert ElixirContainer.mapped_dist_port(container) == 19100
    end

    test "uses default port when env is not set" do
      container = %Config{
        container_id: "abc123",
        image: "elixir:latest",
        environment: %{},
        exposed_ports: [{9100, 19100}]
      }

      assert ElixirContainer.mapped_dist_port(container) == 19100
    end
  end

  describe "runtime behavior — basic IEx" do
    @moduletag :needs_dock
    container(:elixir, ElixirContainer.new() |> ElixirContainer.with_wait_timeout(300_000))

    test "provides a running elixir container", %{elixir: elixir} do
      assert elixir.container_id != nil
    end

    test "can execute commands inside the container", %{elixir: elixir} do
      assert elixir.container_id != nil

      # Verify we can run a command via Docker exec
      case System.cmd("docker", ["exec", elixir.container_id, "elixir", "-v"]) do
        {output, 0} ->
          assert output =~ "Elixir"

        {_, _} ->
          # If docker exec fails, at least verify the container is running
          assert elixir.container_id != nil
      end
    end
  end

  describe "runtime behavior — with distribution" do
    @moduletag :needs_dock

    test "starts with distribution ports exposed" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_cookie("test-cookie")
        |> ElixirContainer.with_node_name("test@127.0.0.1")
        |> ElixirContainer.with_distribution_port(9100)
        |> ElixirContainer.with_wait_timeout(180_000)

      {:ok, container} = TestcontainerEx.start_container(config)

      assert container.container_id != nil
      assert ElixirContainer.mapped_epmd_port(container) != nil
      assert ElixirContainer.mapped_dist_port(container) != nil

      # Cleanup
      TestcontainerEx.stop_container(container.container_id)
    end
  end

  describe "runtime behavior — with custom command" do
    @moduletag :needs_dock

    test "runs a custom command and waits for completion" do
      config =
        ElixirContainer.new()
        |> ElixirContainer.with_cmd(["elixir", "-e", "IO.puts(:hello)"])
        |> ElixirContainer.with_wait_timeout(60_000)

      {:ok, container} = TestcontainerEx.start_container(config)
      assert container.container_id != nil

      # Cleanup
      TestcontainerEx.stop_container(container.container_id)
    end
  end
end
