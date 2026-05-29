defmodule TestcontainerEx.Compose.Cli do
  @moduledoc """
  Subprocess wrapper for Docker Compose CLI interaction.

  Supports both Docker and Podman compose providers. The compose command is
  auto-detected in the following order:

  1. `CONTAINER_COMPOSE_PROVIDER` / `PODMAN_COMPOSE_PROVIDER` env var
  2. `podman compose` (podman 4+ built-in)
  3. `docker` (default fallback)
  """

  require Logger

  alias TestcontainerEx.DockerCompose

  @doc """
  Returns the compose command binary to use.

  Auto-detects the available compose provider with the following precedence:

  1. The `CONTAINER_COMPOSE_PROVIDER` or `PODMAN_COMPOSE_PROVIDER` environment variable.
  2. `podman` if it supports the `compose` subcommand (podman 4+).
  3. `docker` as the default fallback.

  The result is cached after the first call.
  """
  def compose_command do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        cmd = detect_compose_command()
        :persistent_term.put(__MODULE__, cmd)
        cmd

      cmd ->
        cmd
    end
  end

  defp detect_compose_command do
    cond do
      System.get_env("CONTAINER_COMPOSE_PROVIDER") ->
        System.get_env("CONTAINER_COMPOSE_PROVIDER")

      System.get_env("PODMAN_COMPOSE_PROVIDER") ->
        System.get_env("PODMAN_COMPOSE_PROVIDER")

      podman_compose_available?() ->
        "podman"

      true ->
        "docker"
    end
  end

  defp podman_compose_available? do
    case System.cmd("podman", ["compose", "version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    ErlangError -> false
  end

  @doc """
  Runs `docker compose up -d --wait` with the given compose configuration.
  """
  def up(%DockerCompose{} = compose) do
    args = build_up_args(compose)

    case execute(compose, args) do
      {_output, 0} -> :ok
      {output, exit_code} -> {:error, {:compose_up_failed, exit_code, output}}
    end
  end

  @doc """
  Runs `docker compose down` with the given compose configuration.
  """
  def down(%DockerCompose{} = compose) do
    args = build_down_args(compose)

    case execute(compose, args) do
      {_output, 0} -> :ok
      {output, exit_code} -> {:error, {:compose_down_failed, exit_code, output}}
    end
  end

  @doc """
  Runs `docker compose ps --format=json` and parses the output into a list of maps.
  """
  def ps(%DockerCompose{} = compose) do
    args = build_ps_args(compose)

    case execute(compose, args) do
      {output, 0} -> {:ok, parse_ps_output(output)}
      {output, exit_code} -> {:error, {:compose_ps_failed, exit_code, output}}
    end
  end

  @doc """
  Runs `docker compose pull` with the given compose configuration.
  """
  def pull(%DockerCompose{} = compose) do
    args = build_pull_args(compose)

    case execute(compose, args) do
      {_output, 0} -> :ok
      {output, exit_code} -> {:error, {:compose_pull_failed, exit_code, output}}
    end
  end

  @doc """
  Runs `docker compose logs <service>` and returns the output.
  """
  def logs(%DockerCompose{} = compose, service_name) when is_binary(service_name) do
    args = build_logs_args(compose, service_name)

    case execute(compose, args) do
      {output, 0} -> {:ok, output}
      {output, exit_code} -> {:error, {:compose_logs_failed, exit_code, output}}
    end
  end

  # Command building functions - public for testability

  @doc """
  Builds the argument list for `docker compose up`.
  """
  def build_up_args(%DockerCompose{} = compose) do
    base_args(compose) ++ ["up", "-d", "--wait"] ++ build_args(compose) ++ compose.services
  end

  @doc """
  Builds the argument list for `docker compose down`.
  """
  def build_down_args(%DockerCompose{} = compose) do
    args = base_args(compose) ++ ["down"]

    if compose.remove_volumes do
      args ++ ["-v"]
    else
      args
    end
  end

  @doc """
  Builds the argument list for `docker compose ps`.
  """
  def build_ps_args(%DockerCompose{} = compose) do
    base_args(compose) ++ ["ps", "--format=json"]
  end

  @doc """
  Builds the argument list for `docker compose pull`.
  """
  def build_pull_args(%DockerCompose{} = compose) do
    base_args(compose) ++ ["pull"]
  end

  @doc """
  Builds the argument list for `docker compose logs`.
  """
  def build_logs_args(%DockerCompose{} = compose, service_name) do
    base_args(compose) ++ ["logs", service_name]
  end

  @doc """
  Parses the JSON output from `docker compose ps`.

  Each line is a separate JSON object with fields like Service, ID, State, Publishers.
  """
  def parse_ps_output(output) when is_binary(output) do
    output
    |> String.trim()
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, %{} = parsed} ->
          [parsed]

        {:ok, list} when is_list(list) ->
          list

        {:error, _} ->
          []
      end
    end)
  end

  @doc """
  Parses the Publishers field from a `docker compose ps` JSON entry
  into a list of `{container_port, host_port}` tuples.
  """
  def parse_publishers(nil), do: []
  def parse_publishers([]), do: []

  def parse_publishers(publishers) when is_list(publishers) do
    publishers
    |> Enum.filter(fn pub ->
      published = Map.get(pub, "PublishedPort", 0)
      published != 0
    end)
    |> Enum.map(fn pub ->
      target = Map.get(pub, "TargetPort", 0)
      published = Map.get(pub, "PublishedPort", 0)
      {target, published}
    end)
    |> Enum.uniq()
  end

  # Private functions

  defp base_args(%DockerCompose{} = compose) do
    args = ["compose"]

    args =
      if compose.project_name do
        args ++ ["-p", compose.project_name]
      else
        args
      end

    args =
      Enum.reduce(compose.compose_files, args, fn file, acc ->
        acc ++ ["-f", file]
      end)

    Enum.reduce(compose.profiles, args, fn profile, acc ->
      acc ++ ["--profile", profile]
    end)
  end

  defp build_args(%DockerCompose{} = compose) do
    args = []

    args =
      if compose.build do
        args ++ ["--build"]
      else
        args
      end

    case compose.pull do
      :always -> args ++ ["--pull", "always"]
      :never -> args ++ ["--pull", "never"]
      :missing -> args
    end
  end

  defp execute(%DockerCompose{} = compose, args) do
    dir = resolve_directory(compose.filepath)
    env_vars = Enum.map(compose.env, fn {k, v} -> {to_string(k), to_string(v)} end)
    cmd = compose_command()

    Logger.debug("Running: #{cmd} #{Enum.join(args, " ")} in #{dir}")

    System.cmd(cmd, args, cd: dir, env: env_vars, stderr_to_stdout: true)
  end

  defp resolve_directory(filepath) do
    if File.dir?(filepath) do
      filepath
    else
      Path.dirname(filepath)
    end
  end
end
