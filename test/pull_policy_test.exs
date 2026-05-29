defmodule TestcontainerEx.PullPolicyTest do
  use ExUnit.Case, async: true

  alias TestcontainerEx.Connection
  alias TestcontainerEx.Container
  alias TestcontainerEx.Docker.Api
  alias TestcontainerEx.PullPolicy

  @moduletag :needs_registry

  test "always_pull/0 fetches image from remote repository" do
    config = %Container{
      image: "alpine:latest",
      pull_policy: PullPolicy.always_pull()
    }

    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end

  test "never_pull/0 does not fetch image from remote repository" do
    {conn, _url, _host} = Connection.get_connection()
    {:ok, _nil} = Api.pull_image("alpine:latest", conn)
    {:ok, _name} = Api.tag_image("alpine", "local_alpine", "latest", conn)

    config = %Container{
      image: "local_alpine:latest",
      pull_policy: PullPolicy.never_pull()
    }

    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end

  test "pull_condition/1 fetches image if expression evaluates to true" do
    config = %Container{
      image: "alpine:latest",
      pull_policy:
        PullPolicy.pull_condition(fn _config, _conn ->
          true
        end)
    }

    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end

  test "pull_condition/1 does not fetch image if expression evaluates to a falsey value" do
    {conn, _url, _host} = Connection.get_connection()
    {:ok, _nil} = Api.pull_image("alpine:latest", conn)
    {:ok, _name} = Api.tag_image("alpine", "local_alpine2", "latest", conn)

    config = %Container{
      image: "local_alpine2:latest",
      pull_policy:
        PullPolicy.pull_condition(fn _config, _conn ->
          false
        end)
    }

    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end

  test "pull_if_missing/0 starts a container when image already exists locally" do
    {conn, _url, _host} = Connection.get_connection()
    {:ok, _nil} = Api.pull_image("alpine:latest", conn)
    {:ok, _name} = Api.tag_image("alpine", "local_alpine3", "latest", conn)

    config = %Container{
      image: "local_alpine3:latest",
      pull_policy: PullPolicy.pull_if_missing()
    }

    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end

  test "pull_if_missing/0 fetches image when not present locally" do
    {conn, _url, _host} = Connection.get_connection()
    _ = Api.delete_image("alpine:3.19", conn)

    config = %Container{
      image: "alpine:3.19",
      pull_policy: PullPolicy.pull_if_missing()
    }

    assert {:ok, container} = TestcontainerEx.start_container(config)
    assert :ok = TestcontainerEx.stop_container(container.container_id)
  end
end
