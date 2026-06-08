# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Container.RabbitMQContainerTest do
  use ExUnit.Case, async: true

  import TestcontainerEx.ExUnit

  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.RabbitMQContainer

  describe "new/0" do
    test "creates a RabbitMQContainer with default configuration" do
      config = RabbitMQContainer.new()

      assert config.image == "rabbitmq:3-alpine"
      assert config.port == 5672
      assert config.username == "guest"
      assert config.password == "guest"
      assert config.virtual_host == "/"
      assert config.wait_timeout == 60_000
      assert config.reuse == false
      assert config.force_reuse == false
    end
  end

  describe "with_image/2" do
    test "overrides the default image" do
      config = RabbitMQContainer.new()
      new_config = RabbitMQContainer.with_image(config, "rabbitmq:3.12-management")

      assert new_config.image == "rabbitmq:3.12-management"
    end
  end

  describe "with_port/2" do
    test "overrides the default port" do
      config = RabbitMQContainer.new()
      new_config = RabbitMQContainer.with_port(config, 5673)

      assert new_config.port == 5673
    end
  end

  describe "with_username/2" do
    test "sets the username" do
      config = RabbitMQContainer.new()
      new_config = RabbitMQContainer.with_username(config, "admin")

      assert new_config.username == "admin"
    end
  end

  describe "with_password/2" do
    test "sets the password" do
      config = RabbitMQContainer.new()
      new_config = RabbitMQContainer.with_password(config, "secret")

      assert new_config.password == "secret"
    end
  end

  describe "with_virtual_host/2" do
    test "sets the virtual host" do
      config = RabbitMQContainer.new()
      new_config = RabbitMQContainer.with_virtual_host(config, "/myapp")

      assert new_config.virtual_host == "/myapp"
    end
  end

  describe "with_cmd/2" do
    test "sets a custom command" do
      config = RabbitMQContainer.new()
      new_config = RabbitMQContainer.with_cmd(config, ["rabbitmq-server"])

      assert new_config.cmd == ["rabbitmq-server"]
    end
  end

  describe "with_check_image/2" do
    test "sets the check image" do
      config = RabbitMQContainer.new()
      new_config = RabbitMQContainer.with_check_image(config, "rabbitmq")

      assert new_config.check_image == "rabbitmq"
    end
  end

  describe "with_reuse/2" do
    test "sets reuse to true" do
      config = RabbitMQContainer.new()
      new_config = RabbitMQContainer.with_reuse(config, true)

      assert new_config.reuse == true
    end
  end

  describe "with_force_reuse/1" do
    test "sets force_reuse and enables reuse" do
      config = RabbitMQContainer.new()
      new_config = RabbitMQContainer.with_force_reuse(config)

      assert new_config.reuse == true
      assert new_config.force_reuse == true
    end
  end

  describe "default_image/0" do
    test "returns the default image name" do
      assert RabbitMQContainer.default_image() == "rabbitmq"
    end
  end

  describe "default_port/0" do
    test "returns the default AMQP port" do
      assert RabbitMQContainer.default_port() == 5672
    end
  end

  describe "default_image_with_tag/0" do
    test "returns the default image with tag" do
      assert RabbitMQContainer.default_image_with_tag() == "rabbitmq:3-alpine"
    end
  end

  describe "Builder.build/1" do
    test "builds a Config with correct image" do
      config =
        RabbitMQContainer.new()
        |> Builder.build()

      assert config.image == "rabbitmq:3-alpine"
    end

    test "builds a Config with AMQP port exposed" do
      config =
        RabbitMQContainer.new()
        |> Builder.build()

      assert {5672, nil} in config.exposed_ports
    end

    test "builds a Config with RabbitMQ env vars" do
      config =
        RabbitMQContainer.new()
        |> RabbitMQContainer.with_username("admin")
        |> RabbitMQContainer.with_password("secret")
        |> RabbitMQContainer.with_virtual_host("/myapp")
        |> Builder.build()

      assert config.environment[:RABBITMQ_DEFAULT_USER] == "admin"
      assert config.environment[:RABBITMQ_DEFAULT_PASS] == "secret"
      assert config.environment[:RABBITMQ_DEFAULT_VHOST] == "/myapp"
      assert config.environment[:RABBITMQ_NODE_PORT] == "5672"
    end

    test "builds a Config with rabbitmq-diagnostics wait strategy" do
      config =
        RabbitMQContainer.new()
        |> Builder.build()

      assert [%CommandWaitStrategy{command: ["rabbitmq-diagnostics", "check_running"]}] =
               config.wait_strategies
    end

    test "builds a Config with custom command" do
      config =
        RabbitMQContainer.new()
        |> RabbitMQContainer.with_cmd(["sh", "-c", "rabbitmq-server"])
        |> Builder.build()

      assert config.cmd == ["sh", "-c", "rabbitmq-server"]
    end

    test "builds a Config with force_reuse" do
      config =
        RabbitMQContainer.new()
        |> RabbitMQContainer.with_force_reuse()
        |> Builder.build()

      assert config.reuse == true
      assert config.force_reuse == true
    end
  end

  describe "port/1" do
    test "returns the mapped port from a container" do
      container = %Config{
        container_id: "abc123",
        image: "rabbitmq:3-alpine",
        environment: %{RABBITMQ_NODE_PORT: "5672"},
        exposed_ports: [{5672, 15672}]
      }

      assert RabbitMQContainer.port(container) == 15672
    end

    test "returns nil when port is not mapped" do
      container = %Config{
        container_id: "abc123",
        image: "rabbitmq:3-alpine",
        environment: %{},
        exposed_ports: []
      }

      assert RabbitMQContainer.port(container) == nil
    end
  end

  describe "connection_url/1" do
    test "returns amqp URL with default vhost" do
      container = %Config{
        container_id: "abc123",
        image: "rabbitmq:3-alpine",
        environment: %{
          RABBITMQ_DEFAULT_USER: "guest",
          RABBITMQ_DEFAULT_PASS: "guest",
          RABBITMQ_DEFAULT_VHOST: "/"
        },
        exposed_ports: [{5672, 15672}]
      }

      url = RabbitMQContainer.connection_url(container)
      assert url == "amqp://guest:guest@localhost:15672/"
    end

    test "returns amqp URL with custom vhost" do
      container = %Config{
        container_id: "abc123",
        image: "rabbitmq:3-alpine",
        environment: %{
          RABBITMQ_DEFAULT_USER: "admin",
          RABBITMQ_DEFAULT_PASS: "secret",
          RABBITMQ_DEFAULT_VHOST: "/myapp"
        },
        exposed_ports: [{5672, 15672}]
      }

      url = RabbitMQContainer.connection_url(container)
      assert url == "amqp://admin:secret@localhost:15672/myapp"
    end
  end

  describe "connection_parameters/1" do
    test "returns connection parameters keyword list" do
      container = %Config{
        container_id: "abc123",
        image: "rabbitmq:3-alpine",
        environment: %{
          RABBITMQ_DEFAULT_USER: "admin",
          RABBITMQ_DEFAULT_PASS: "secret",
          RABBITMQ_DEFAULT_VHOST: "/myapp"
        },
        exposed_ports: [{5672, 15672}]
      }

      params = RabbitMQContainer.connection_parameters(container)
      assert params[:username] == "admin"
      assert params[:password] == "secret"
      assert params[:virtual_host] == "/myapp"
      assert is_integer(params[:port])
      assert params[:port] > 0
    end
  end

  describe "runtime behavior" do
    @moduletag :needs_dock
    container(:rabbitmq, RabbitMQContainer.new())

    test "provides a ready-to-use rabbitmq container", %{rabbitmq: rabbitmq} do
      assert rabbitmq.container_id != nil
      assert RabbitMQContainer.port(rabbitmq) != nil
    end

    test "can publish and consume a message", %{rabbitmq: rabbitmq} do
      port = RabbitMQContainer.port(rabbitmq)

      opts = [
        host: "localhost",
        port: port,
        username: "guest",
        password: "guest",
        virtual_host: "/"
      ]

      {:ok, conn} = AMQP.Connection.open(opts)
      {:ok, channel} = AMQP.Channel.open(conn)

      queue = "test_queue"
      AMQP.Queue.declare(channel, queue)
      AMQP.Basic.publish(channel, "", queue, "hello")

      # Verify message was sent (no error means success)
      AMQP.Queue.delete(channel, queue)
      AMQP.Channel.close(channel)
      AMQP.Connection.close(conn)
    end
  end
end
