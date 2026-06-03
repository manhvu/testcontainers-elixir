defmodule TestcontainerEx.HttpWaitStrategyTest do
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.HttpWaitStrategy
  use ExUnit.Case, async: true

  @moduletag :needs_dock

  test "can wait for a http request and retrieve content" do
    port = 80

    config =
      %Config{image: "nginx:alpine"}
      |> Config.with_exposed_port(port)
      |> Config.with_waiting_strategy(HttpWaitStrategy.new("/", port))

    assert {:ok, container} = TestcontainerEx.start_container(config)

    host = TestcontainerEx.get_host(container)
    host_port = TestcontainerEx.get_port(container, port)
    url = ~c"http://#{host}:#{host_port}/"
    {:ok, {_status, _headers, body}} = :httpc.request(:get, {url, []}, [], [])
    assert to_string(body) =~ "Welcome to nginx!"

    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end

  test "can wait for a specific status code" do
    port = 80

    config =
      %Config{image: "nginx:alpine"}
      |> Config.with_exposed_port(port)
      |> Config.with_waiting_strategy(HttpWaitStrategy.new("/", port, status_code: 200))

    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end

  test "fails when status code does not match" do
    port = 80

    config =
      %Config{image: "nginx:alpine"}
      |> Config.with_exposed_port(port)
      |> Config.with_waiting_strategy(
        HttpWaitStrategy.new("/", port, status_code: 999, timeout: 5000, max_retries: 1)
      )

    assert {:error, _, %HttpWaitStrategy{}} = TestcontainerEx.start_container(config)
  end

  test "can use a custom match function" do
    port = 80

    config =
      %Config{image: "nginx:alpine"}
      |> Config.with_exposed_port(port)
      |> Config.with_waiting_strategy(
        HttpWaitStrategy.new("/", port,
          match: fn response -> response.body =~ "Welcome to nginx!" end
        )
      )

    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end

  test "fails when custom match function returns false" do
    port = 80

    config =
      %Config{image: "nginx:alpine"}
      |> Config.with_exposed_port(port)
      |> Config.with_waiting_strategy(
        HttpWaitStrategy.new("/", port,
          timeout: 5000,
          max_retries: 1,
          match: fn _response -> false end
        )
      )

    assert {:error, _, %HttpWaitStrategy{}} = TestcontainerEx.start_container(config)
  end
end
