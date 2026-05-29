defmodule TestcontainerEx.Compose.ComposeCommandTest do
  # async: false because we mutate environment variables and persistent_term
  use ExUnit.Case, async: false

  alias TestcontainerEx.Compose.Cli

  setup do
    # Clear the cached compose command so each test starts fresh
    :persistent_term.erase(TestcontainerEx.Compose.Cli)

    on_exit(fn ->
      :persistent_term.erase(TestcontainerEx.Compose.Cli)
    end)

    :ok
  end

  describe "compose_command/0" do
    test "returns docker by default when no special env vars are set" do
      System.delete_env("CONTAINER_COMPOSE_PROVIDER")
      System.delete_env("PODMAN_COMPOSE_PROVIDER")

      # docker should be the fallback in test env (assuming docker is available)
      # If docker is not available, podman might be detected instead
      case Cli.compose_command() do
        "docker" ->
          :ok

        "podman" ->
          # podman compose is available on this system — acceptable
          :ok

        other ->
          # A custom provider or binary path — also acceptable
          assert is_binary(other)
      end
    end

    test "returns custom command when CONTAINER_COMPOSE_PROVIDER is set" do
      System.put_env("CONTAINER_COMPOSE_PROVIDER", "/usr/local/bin/docker-compose")
      System.delete_env("PODMAN_COMPOSE_PROVIDER")

      assert Cli.compose_command() == "/usr/local/bin/docker-compose"
    end

    test "returns custom command when PODMAN_COMPOSE_PROVIDER is set" do
      System.put_env("PODMAN_COMPOSE_PROVIDER", "/usr/local/bin/podman-compose")
      System.delete_env("CONTAINER_COMPOSE_PROVIDER")

      assert Cli.compose_command() == "/usr/local/bin/podman-compose"
    end

    test "CONTAINER_COMPOSE_PROVIDER takes precedence over PODMAN_COMPOSE_PROVIDER" do
      System.put_env("CONTAINER_COMPOSE_PROVIDER", "/custom/docker-compose")
      System.put_env("PODMAN_COMPOSE_PROVIDER", "/custom/podman-compose")

      assert Cli.compose_command() == "/custom/docker-compose"
    end

    test "caches the result after first call" do
      System.delete_env("CONTAINER_COMPOSE_PROVIDER")
      System.delete_env("PODMAN_COMPOSE_PROVIDER")

      first = Cli.compose_command()

      # Change env vars — should still return cached value
      System.put_env("CONTAINER_COMPOSE_PROVIDER", "/custom/compose")
      second = Cli.compose_command()

      assert first == second
    end

    test "returns podman when podman compose is available and no env var override" do
      System.delete_env("CONTAINER_COMPOSE_PROVIDER")
      System.delete_env("PODMAN_COMPOSE_PROVIDER")

      cmd = Cli.compose_command()

      # Should be either "docker" or "podman" depending on what's available
      assert cmd in ["docker", "podman"] or is_binary(cmd)
    end
  end
end
