defmodule Mix.Tasks.TestcontainerEx.Test do
  @moduledoc """
  Runs Docker-dependent tests with automatic Ryuk setup and teardown.

  This task handles the full lifecycle:
    1. Ensures Docker is available (starts Colima if needed)
    2. Starts a Ryuk reaper container for automatic test container cleanup
    3. Runs the requested tests (including :needs_dock tests)
    4. Stops Ryuk and cleans up on completion

  ## Usage

      # Run all tests including Docker-dependent ones
      mix testcontainer_ex.test

      # Run only Docker-dependent tests
      mix testcontainer_ex.test --only needs_dock

      # Run a specific test file
      mix testcontainer_ex.test test/container/postgres_container_test.exs

      # Run with a specific tag
      mix testcontainer_ex.test --include needs_dock --exclude dood_limitation

      # Only set up Ryuk (don't run tests)
      mix testcontainer_ex.test --setup-only

      # Tear down Ryuk and clean up
      mix testcontainer_ex.test --teardown

  ## Options

      --setup-only    Start Ryuk and exit (don't run tests)
      --teardown      Stop Ryuk and clean up test containers
      --only TAG      Run only tests with this tag (can be repeated)
      --include TAG   Include tests with this tag (passed to mix test)
      --exclude TAG   Exclude tests with this tag (passed to mix test)

  ## Environment variables

      RYUK_IMAGE      Ryuk image (default: testcontainers/ryuk:0.14.0)
      RYUK_PORT       Host port for Ryuk (default: auto)
      TEST_TIMEOUT    Timeout in ms (default: 300000)
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [
          setup_only: :boolean,
          teardown: :boolean,
          only: :string,
          include: :string,
          exclude: :string
        ]
      )

    if opts[:teardown] do
      teardown()
    else
      setup()

      if opts[:setup_only] != true do
        run_tests(rest, opts)
      end
    end
  end

  # ── Docker check ──────────────────────────────────────────────────────────────

  defp ensure_docker! do
    case System.find_executable("docker") do
      nil ->
        Mix.raise("Docker is not installed or not in PATH")

      _docker ->
        :ok
    end
  end

  defp ensure_colima! do
    if System.find_executable("colima") do
      case System.cmd("colima", ["status"], stderr_to_stdout: true) do
        {_, 0} ->
          Mix.shell().info("[testcontainer_ex] Colima is running")

        _ ->
          Mix.shell().info("[testcontainer_ex] Starting Colima...")
          {_, 0} = System.cmd("colima", ["start"], stderr_to_stdout: true)
          Mix.shell().info("[testcontainer_ex] Colima started")
      end
    end
  end

  defp wait_for_docker! do
    Mix.shell().info("[testcontainer_ex] Waiting for Docker daemon...")

    1..60
    |> Enum.reduce_while(:timeout, fn _attempt, _acc ->
      case System.cmd("docker", ["info"], stderr_to_stdout: true) do
        {_, 0} ->
          Mix.shell().info("[testcontainer_ex] Docker daemon is ready")
          {:halt, :ok}

        _ ->
          Process.sleep(1_000)
          {:cont, :timeout}
      end
    end)
    |> case do
      :ok -> :ok
      :timeout -> Mix.raise("Docker daemon did not become ready after 60s")
    end
  end

  defp docker_socket_paths do
    [
      "/var/run/docker.sock",
      Path.expand("~/.docker/run/docker.sock"),
      Path.expand("~/.docker/desktop/docker.sock"),
      Path.expand("~/.colima/default/docker.sock"),
      Path.expand("~/.colima/docker.sock")
    ]
  end

  defp detect_docker_socket_path do
    Enum.find_value(docker_socket_paths(), fn path ->
      case File.stat(path) do
        {:ok, stat} ->
          if :erlang.band(stat.mode, 0o170000) == 0o140000 do
            path
          end

        _ ->
          nil
      end
    end) || Mix.raise("Could not find Docker socket")
  end

  # ── Ryuk management ───────────────────────────────────────────────────────────

  defp start_ryuk do
    ryuk_image = System.get_env("RYUK_IMAGE", "testcontainers/ryuk:0.14.0")
    container_name = "testcontainer_ex-ryuk-#{:erlang.unique_integer([:positive])}"

    # Clean up orphaned Ryuk containers
    System.cmd(
      "docker",
      ["ps", "-a", "--filter", "name=testcontainer_ex-ryuk", "--format", "{{.ID}}"],
      stderr_to_stdout: true
    )
    |> elem(0)
    |> String.split("\n", trim: true)
    |> Enum.each(fn id ->
      System.cmd("docker", ["rm", "-f", id], stderr_to_stdout: true)
    end)

    # Pull Ryuk image
    Mix.shell().info("[testcontainer_ex] Pulling Ryuk image: #{ryuk_image}")
    {_, 0} = System.cmd("docker", ["pull", ryuk_image], stderr_to_stdout: true)

    # Detect Docker socket
    docker_socket_path = detect_docker_socket_path()
    Mix.shell().info("[testcontainer_ex] Using Docker socket: #{docker_socket_path}")
    System.put_env("CONTAINER_ENGINE_HOST", "unix://#{docker_socket_path}")

    # Determine how to give Ryuk access to Docker:
    # - Linux: bind-mount the Docker socket directly
    # - macOS (Colima/Docker Desktop): use host network or TCP, because the
    #   socket path is inside a VM that containers can't bind-mount from the host
    os_type = os_type()

    mount_args =
      case os_type do
        :linux ->
          ["-v", "#{docker_socket_path}:/var/run/docker.sock"]

        :macos ->
          ["--network", "host"]

        :windows ->
          ["-v", "//var/run/docker.sock:/var/run/docker.sock"]
      end

    # Start Ryuk container
    ryuk_port = System.get_env("RYUK_PORT", "0")
    port_arg = if ryuk_port == "0", do: "-p", else: "-p#{ryuk_port}:8080"

    docker_args =
      [
        "run",
        "-d",
        "--name",
        container_name,
        "--restart",
        "unless-stopped"
      ] ++
        mount_args ++
        if os_type == :macos do
          # With --network host, -p is not needed
          ["--privileged", ryuk_image]
        else
          [port_arg, "8080", "--privileged", ryuk_image]
        end

    {output, 0} =
      System.cmd("docker", docker_args, stderr_to_stdout: true)

    ryuk_id = String.trim(output)
    Mix.shell().info("[testcontainer_ex] Ryuk container started: #{String.slice(ryuk_id, 0, 12)}")

    # Store PID for cleanup
    pid_file = Path.join(System.tmp_dir!(), "testcontainer_ex-ryuk.pid")
    File.write!(pid_file, "#{container_name}\n#{ryuk_id}\n")

    # Wait for Ryuk to be ready
    Mix.shell().info("[testcontainer_ex] Waiting for Ryuk to be ready...")
    Process.sleep(3_000)

    case System.cmd("docker", ["inspect", "--format", "{{.State.Running}}", ryuk_id],
           stderr_to_stdout: true
         ) do
      {"true\n", 0} ->
        Mix.shell().info("[testcontainer_ex] Ryuk is running")

      _ ->
        Mix.shell().info(
          "[testcontainer_ex] Ryuk container may not be healthy, continuing anyway"
        )
    end

    # Register cleanup via System.at_exit
    System.at_exit(fn _ ->
      teardown_ryuk(container_name)
      :ok
    end)
  end

  defp os_type do
    case :os.type() do
      {:win32, _} -> :windows
      {:unix, :darwin} -> :macos
      {:unix, _} -> :linux
    end
  end

  defp setup do
    ensure_docker!()
    ensure_colima!()
    wait_for_docker!()
    start_ryuk()
  end

  defp teardown do
    pid_file = Path.join(System.tmp_dir!(), "testcontainer_ex-ryuk.pid")

    if File.exists?(pid_file) do
      [container_name | _] = File.read!(pid_file) |> String.split("\n")
      teardown_ryuk(container_name)
      File.rm!(pid_file)
    else
      # Try to find any Ryuk containers
      {output, 0} =
        System.cmd(
          "docker",
          ["ps", "-a", "--filter", "name=testcontainer_ex-ryuk", "--format", "{{.Names}}"],
          stderr_to_stdout: true
        )

      output
      |> String.split("\n", trim: true)
      |> Enum.each(&teardown_ryuk/1)
    end

    # Clean up test containers
    Mix.shell().info("[testcontainer_ex] Cleaning up test containers...")

    System.cmd(
      "docker",
      ["ps", "-a", "--filter", "label=org.testcontainer_ex", "--format", "{{.ID}}"],
      stderr_to_stdout: true
    )
    |> elem(0)
    |> String.split("\n", trim: true)
    |> Enum.each(fn id ->
      System.cmd("docker", ["rm", "-f", id], stderr_to_stdout: true)
    end)

    Mix.shell().info("[testcontainer_ex] Cleanup complete")
  end

  defp teardown_ryuk(container_name) do
    case System.cmd("docker", ["ps", "--filter", "name=#{container_name}", "--format", "{{.ID}}"],
           stderr_to_stdout: true
         ) do
      {"", _} ->
        :ok

      {id, _} ->
        id = String.trim(id)
        Mix.shell().info("[testcontainer_ex] Stopping Ryuk: #{String.slice(id, 0, 12)}")
        System.cmd("docker", ["stop", id], stderr_to_stdout: true)
        System.cmd("docker", ["rm", id], stderr_to_stdout: true)
        Mix.shell().info("[testcontainer_ex] Ryuk removed")
    end
  end

  # ── Test execution ────────────────────────────────────────────────────────────

  defp run_tests(rest, opts) do
    timeout = String.to_integer(System.get_env("TEST_TIMEOUT", "300000"))

    mix_test_args = [
      "--exclude",
      "flaky",
      "--timeout",
      to_string(timeout)
    ]

    # Handle --only tag
    mix_test_args =
      case opts[:only] do
        nil -> mix_test_args
        _tag -> mix_test_args ++ ["--include", "needs_dock", "--exclude", "dood_limitation"]
      end

    # Handle --include tags
    mix_test_args =
      case opts[:include] do
        nil -> mix_test_args
        tag -> mix_test_args ++ ["--include", tag]
      end

    # Handle --exclude tags
    mix_test_args =
      case opts[:exclude] do
        nil -> mix_test_args
        tag -> mix_test_args ++ ["--exclude", tag]
      end

    # Add any remaining args (test files, line numbers, etc.)
    all_args = mix_test_args ++ rest

    Mix.shell().info("[testcontainer_ex] Running: mix test #{Enum.join(all_args, " ")}")

    {_, exit_code} =
      System.cmd("mix", ["test" | all_args],
        into: IO.stream(:stdio, :line),
        env: [{"MIX_ENV", "test"}]
      )

    if exit_code != 0 do
      Mix.raise("mix test failed with exit code #{exit_code}")
    end
  end
end
