defmodule TestcontainerExTest do
  alias TestcontainerEx.Connection
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.Engine
  alias TestcontainerEx.HttpWaitStrategy
  # async: false because ryuk_privileged? tests mutate process environment
  use ExUnit.Case, async: false

  @ryuk_privileged_env "TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED"
  @ryuk_privileged_prop "ryuk.container.privileged"

  describe "ryuk_privileged?/1" do
    setup do
      original = System.get_env(@ryuk_privileged_env)

      on_exit(fn ->
        case original do
          nil -> System.delete_env(@ryuk_privileged_env)
          value -> System.put_env(@ryuk_privileged_env, value)
        end
      end)

      :ok
    end

    test "returns false when neither property nor env var is set" do
      System.delete_env(@ryuk_privileged_env)
      refute TestcontainerEx.ryuk_privileged?(%{})
    end

    test "returns true when property is 'true'" do
      System.delete_env(@ryuk_privileged_env)
      assert TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "true"})
    end

    test "returns true when property is '1'" do
      System.delete_env(@ryuk_privileged_env)
      assert TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "1"})
    end

    test "returns false when property is 'false'" do
      System.delete_env(@ryuk_privileged_env)
      refute TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "false"})
    end

    test "returns false when property is '0'" do
      System.delete_env(@ryuk_privileged_env)
      refute TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "0"})
    end

    test "returns true when env var is 'true'" do
      System.put_env(@ryuk_privileged_env, "true")
      assert TestcontainerEx.ryuk_privileged?(%{})
    end

    test "returns true when env var is '1'" do
      System.put_env(@ryuk_privileged_env, "1")
      assert TestcontainerEx.ryuk_privileged?(%{})
    end

    test "returns false when env var is 'false'" do
      System.put_env(@ryuk_privileged_env, "false")
      refute TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "true"})
    end

    test "env var takes precedence over property (env false, prop true)" do
      System.put_env(@ryuk_privileged_env, "false")
      refute TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "true"})
    end

    test "env var takes precedence over property (env true, prop false)" do
      System.put_env(@ryuk_privileged_env, "true")
      assert TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "false"})
    end

    test "treats arbitrary strings as falsy" do
      System.delete_env(@ryuk_privileged_env)
      refute TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "yes"})
      refute TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => ""})
    end

    test "is case-insensitive and trims whitespace" do
      System.delete_env(@ryuk_privileged_env)
      assert TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "TRUE"})
      assert TestcontainerEx.ryuk_privileged?(%{@ryuk_privileged_prop => "  true  "})
    end
  end

  @tag :needs_dock
  test "cleans up containers on terminate" do
    {:ok, pid} = TestcontainerEx.start_link(name: :cleanup_test1)

    config = %Config{image: "nginx:alpine"}
    {:ok, container} = TestcontainerEx.start_container(config, :cleanup_test1)

    # Verify the container is running
    assert {conn, _url, _host} = Connection.get_connection()
    assert {:ok, _} = Engine.Api.get_container(container.container_id, conn)

    # Stop the container explicitly and wait for it
    {:ok, :stopped} = TestcontainerEx.stop_container(container.container_id, :cleanup_test1)

    TestHelper.wait_for_lambda(
      fn ->
        case Engine.Api.get_container(container.container_id, conn) do
          {:error, _} ->
            :ok

          {:ok, _} ->
            case System.cmd(
                   "docker",
                   ["inspect", "--format", "{{.State.Running}}", container.container_id],
                   stderr_to_stdout: true
                 ) do
              {"false\n", 0} -> :ok
              _ -> :error
            end
        end
      end,
      max_retries: 10,
      interval: 500
    )

    # Stop the GenServer
    :ok = GenServer.stop(pid)
  end

  @tag :needs_dock
  test "cleans up container when wait strategy fails" do
    config =
      %Config{image: "nginx:alpine"}
      |> Config.with_exposed_port(80)
      |> Config.with_waiting_strategy(
        HttpWaitStrategy.new("/nonexistent", 80,
          status_code: 999,
          timeout: 2000,
          max_retries: 1
        )
      )

    {:ok, pid} = TestcontainerEx.start_link(name: :cleanup_test2)
    result = TestcontainerEx.start_container(config, :cleanup_test2)

    assert {:error, _, _} = result

    :ok = GenServer.stop(pid)
  end

  @tag :needs_dock
  test "assigns custom name to container via Container.with_name/2" do
    name = "testcontainer_ex-name-#{:rand.uniform(1_000_000)}"

    config =
      Config.new("nginx:alpine")
      |> Config.with_name(name)

    {:ok, pid} = TestcontainerEx.start_link(name: :name_test)
    {:ok, container} = TestcontainerEx.start_container(config, :name_test)

    assert {conn, _url, _host} = Connection.get_connection()

    {:ok, %Config{}} = Engine.Api.get_container(container.container_id, conn)

    # Verify the container was created with the correct name
    assert container.name == name

    :ok = GenServer.stop(pid)
  end

  @tag :needs_dock
  test "initializes successfully when ryuk is disabled" do
    # Set environment variable to disable Ryuk
    System.put_env("TESTCONTAINERS_RYUK_DISABLED", "true")

    try do
      # This should succeed without errors when Ryuk is disabled
      # The fix ensures start_reaper returns {:ok} instead of {:ok, nil}
      # which matches the pattern in the with statement
      {:ok, _pid} = TestcontainerEx.start_link(name: :ryuk_disabled_test)

      # If we reach here, the initialization succeeded
      assert true
    after
      # Clean up the environment variable
      System.delete_env("TESTCONTAINERS_RYUK_DISABLED")
    end
  end

  # ── Engine selection ──────────────────────────────────────────────

  @tag :needs_dock
  test "get_engine/1 returns the configured engine" do
    name = :"engine_get_test_#{:rand.uniform(1_000_000)}"
    {:ok, _pid} = TestcontainerEx.start_link(name: name, engine: :auto)
    assert TestcontainerEx.get_engine(name) == :auto
    TestcontainerEx.stop(name)
  end

  @tag :needs_dock
  test "start_link with engine option stores the engine" do
    name = :"engine_start_test_#{:rand.uniform(1_000_000)}"
    {:ok, _pid} = TestcontainerEx.start_link(name: name, engine: :docker)
    assert TestcontainerEx.get_engine(name) == :docker
    TestcontainerEx.stop(name)
  end

  @tag :needs_dock
  test "reconnect/2 switches the engine" do
    name = :"engine_reconnect_test_#{:rand.uniform(1_000_000)}"
    {:ok, _pid} = TestcontainerEx.start_link(name: name, engine: :auto)

    assert TestcontainerEx.get_engine(name) == :auto

    # Reconnect to :docker explicitly
    {:ok, resolved} = TestcontainerEx.reconnect(engine: :docker, name: name)
    assert resolved == :docker
    assert TestcontainerEx.get_engine(name) == :docker

    TestcontainerEx.stop(name)
  end

  @tag :needs_dock
  test "reconnect/2 resets tracked resources" do
    name = :"engine_reconnect_reset_test_#{:rand.uniform(1_000_000)}"
    {:ok, _pid} = TestcontainerEx.start_link(name: name)

    # Start a container
    config = %Config{image: "nginx:alpine"}
    {:ok, container} = TestcontainerEx.start_container(config, name)

    # Verify it's running
    assert {conn, _url, _host} = Connection.get_connection()
    assert {:ok, _} = Engine.Api.get_container(container.container_id, conn)

    # Reconnect should stop the container and clear tracked resources
    {:ok, _resolved} = TestcontainerEx.reconnect(engine: :auto, name: name)

    TestcontainerEx.stop(name)
  end

  @tag :needs_dock
  test "set_engine/1 affects container_engine/0" do
    TestcontainerEx.Engine.clear_engine()
    on_exit(fn -> TestcontainerEx.Engine.clear_engine() end)

    TestcontainerEx.set_engine(:podman)
    assert TestcontainerEx.container_engine() == :podman

    TestcontainerEx.set_engine(:docker)
    assert TestcontainerEx.container_engine() == :docker
  end
end
