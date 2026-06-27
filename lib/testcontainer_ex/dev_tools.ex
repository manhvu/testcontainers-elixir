defmodule TestcontainerEx.DevTools do
  @moduledoc """
  Developer utilities for interacting with running containers at runtime.

  Provides a high-level, iex-friendly API for common container operations
  such as copying files, executing commands, listing contents, and more.

  ## Usage

      iex> {:ok, container} = TestcontainerEx.start_container(PostgresContainer.new())
      iex> TestcontainerEx.DevTools.exec(container, ["psql", "-U", "postgres", "-c", "SELECT 1"])
      {:ok, " ?column? \\n----------\\n        1\\n(1 row)\\n"}
      iex> TestcontainerEx.DevTools.write_file(container, "/tmp/hello.txt", "world")
      :ok
      iex> TestcontainerEx.DevTools.read_file(container, "/tmp/hello.txt")
      {:ok, "world"}
      iex> TestcontainerEx.DevTools.delete_file(container, "/tmp/hello.txt")
      :ok
      iex> TestcontainerEx.DevTools.list_dir(container, "/tmp")
      {:ok, ["file1", "file2"]}

  All functions accept either a `Config.t()` struct or a raw container ID string.
  """

  alias TestcontainerEx.{
    Container.Config,
    Engine.Control
  }

  @type container_ref :: Config.t() | String.t()
  @type exec_result :: {:ok, String.t()} | {:error, term()}

  # ── Command execution ──────────────────────────────────────────────

  @doc """
  Executes a command inside a running container.

  Returns `{:ok, output}` on success or `{:error, reason}` on failure.

  ## Options

    * `:tty` — allocate a TTY (default: `false`)
    * `:workdir` — working directory inside the container
    * `:user` — user (UID or name) to run as
    * `:env` — list of environment variables (e.g. `["FOO=bar", "BAZ=qux"]`)
    * `:timeout` — timeout in ms (default: `30_000`)

  ## Examples

      iex> DevTools.exec(container, ["ls", "-la", "/app"])
      {:ok, "total 12\\ndrwxr-xr-x 2 root root 4096 Jan 1 00:00 .\\n..."}

      iex> DevTools.exec(container, ["psql", "-c", "SELECT 1"], user: "postgres")
      {:ok, " ?column? \\n----------\\n        1\\n(1 row)\\n"}
  """
  @spec exec(container_ref(), [String.t()], keyword()) :: exec_result()
  def exec(container, command, opts \\ []) do
    id = container_id(container)

    with {:ok, exec_id} <- Control.create_exec(id, command, exec_opts(opts)),
         {:ok, output} <- Control.start_exec(exec_id, []) do
      {:ok, output}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Executes a command and returns the output as a list of lines.

  Convenience wrapper around `exec/2` that splits the output by newlines.
  """
  @spec exec_lines(container_ref(), [String.t()], keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def exec_lines(container, command, opts \\ []) do
    case exec(container, command, opts) do
      {:ok, output} -> {:ok, String.split(output, "\n", trim: true)}
      error -> error
    end
  end

  # ── File copy: host → container ───────────────────────────────────

  @doc """
  Copies a file or directory from the host into the container.

  The `source` can be:
  - A file path — the file is read and uploaded to `dest_path`
  - A directory path — the directory is archived and extracted at `dest_path`
  - A binary — uploaded as a file at `dest_path`

  ## Examples

      iex> DevTools.copy_to(container, "/app/config.yml", "config.yml")
      :ok

      iex> DevTools.copy_to(container, "/app/seeds", "/app")
      :ok

      iex> DevTools.copy_to(container, "/tmp/data.json", ~s({"key": "value"}))
      :ok
  """
  @spec copy_to(container_ref(), String.t(), String.t() | binary(), keyword()) ::
          :ok | {:error, term()}
  def copy_to(container, dest_path, source, opts \\ []) do
    id = container_id(container)
    base_url = Keyword.get(opts, :base_url, default_url())

    case source do
      path when is_binary(path) ->
        case File.stat(path) do
          {:ok, %{type: :regular}} ->
            Control.upload(id, dest_path, path, base_url)

          {:ok, %{type: :directory}} ->
            Control.upload(id, dest_path, path, base_url)

          {:error, _reason} ->
            # Not a file on disk — treat as string contents to write
            filename = Path.basename(dest_path)
            tar_data = create_tar(filename, path)
            upload_tar_to_container(id, dest_path, tar_data, base_url)
        end
    end
  end

  @doc """
  Writes string contents to a file inside the container.

  Convenience wrapper around `copy_to/3` for writing text content.

  ## Examples

      iex> DevTools.write_file(container, "/tmp/hello.txt", "world")
      :ok

      iex> DevTools.write_file(container, "/app/config.json", ~s({"debug": true}))
      :ok
  """
  @spec write_file(container_ref(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def write_file(container, dest_path, contents, opts \\ []) when is_binary(contents) do
    copy_to(container, dest_path, contents, opts)
  end

  # ── File copy: container → host ───────────────────────────────────

  @doc """
  Copies a file or directory from the container to the host.

  ## Options

    * `:base_url` — override the Docker engine URL

  ## Examples

      iex> DevTools.copy_from(container, "/app/logs/server.log", "/tmp/server.log")
      :ok

      iex> DevTools.copy_from(container, "/app/data", "/tmp/container_data")
      :ok
  """
  @spec copy_from(container_ref(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def copy_from(container, container_path, host_path, opts \\ []) do
    id = container_id(container)
    base_url = Keyword.get(opts, :base_url, default_url())

    case Control.download(id, container_path, base_url) do
      {:ok, tar_data} ->
        case extract_tar_to_host(tar_data, host_path) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      error ->
        error
    end
  end

  @doc """
  Reads a single file from the container and returns its contents.

  ## Examples

      iex> DevTools.read_file(container, "/app/config.json")
      {:ok, "{\\"debug\\": true}\\n"}

      iex> DevTools.read_file(container, "/nonexistent")
      {:error, :empty_archive}
  """
  @spec read_file(container_ref(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def read_file(container, container_path, opts \\ []) do
    id = container_id(container)
    base_url = Keyword.get(opts, :base_url, default_url())
    Control.download_file(id, container_path, base_url)
  end

  @doc """
  Reads a file from the container and returns its contents as a list of lines.

  Convenience wrapper around `read_file/2`.
  """
  @spec read_lines(container_ref(), String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def read_lines(container, container_path, opts \\ []) do
    case read_file(container, container_path, opts) do
      {:ok, content} -> {:ok, String.split(content, "\n", trim: true)}
      error -> error
    end
  end

  # ── Process management ───────────────────────────────────────────

  @doc """
  Kills a process inside the container by PID.

  ## Options

    * `:signal` — signal to send (default: `"SIGKILL"`)

  ## Examples

      iex> DevTools.kill_process(container, 123)
      :ok

      iex> DevTools.kill_process(container, 456, signal: "SIGTERM")
      :ok
  """
  @spec kill_process(container_ref(), integer(), keyword()) :: :ok | {:error, term()}
  def kill_process(container, pid, opts \\ []) when is_integer(pid) and pid > 0 do
    signal = Keyword.get(opts, :signal, "SIGKILL")

    case exec(container, ["kill", "-#{signal}", to_string(pid)], opts) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Kills processes by name inside the container.

  Uses `pkill` to match against the process name.

  ## Options

    * `:signal` — signal to send (default: `"SIGKILL"`)
    * `:exact` — match exact process name (default: `false`)

  ## Examples

      iex> DevTools.kill_process_name(container, "nginx")
      :ok

      iex> DevTools.kill_process_name(container, "my_app", signal: "SIGTERM", exact: true)
      :ok
  """
  @spec kill_process_name(container_ref(), String.t(), keyword()) :: :ok | {:error, term()}
  def kill_process_name(container, name, opts \\ []) when is_binary(name) do
    signal = Keyword.get(opts, :signal, "SIGKILL")
    flags = if Keyword.get(opts, :exact, false), do: ["-f"], else: []
    cmd = ["pkill", "-#{signal}"] ++ flags ++ [name]

    case exec(container, cmd, opts) do
      {:ok, _} -> :ok
      # pkill returns exit code 1 when no process matched, which is not a failure
      {:error, _} -> :ok
    end
  end

  @doc """
  Finds PIDs by process name inside the container.

  Returns `{:ok, pids}` where `ids` is a list of integer PIDs.

  ## Examples

      iex> DevTools.find_pids(container, "nginx")
      {:ok, [123, 456]}
  """
  @spec find_pids(container_ref(), String.t(), keyword()) :: {:ok, [integer()]} | {:error, term()}
  def find_pids(container, name, opts \\ []) when is_binary(name) do
    case exec(container, ["pgrep", name], opts) do
      {:ok, output} ->
        pids =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&String.to_integer/1)

        {:ok, pids}

      error ->
        error
    end
  end

  # ── File deletion ─────────────────────────────────────────────────

  @doc """
  Deletes a file or directory inside the container.

  Uses `rm -rf` internally, so use with caution.

  ## Examples

      iex> DevTools.delete_file(container, "/tmp/hello.txt")
      :ok

      iex> DevTools.delete_file(container, "/tmp/mydir")
      :ok
  """
  @spec delete_file(container_ref(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_file(container, container_path, opts \\ []) do
    case exec(container, ["rm", "-rf", container_path], opts) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Checks if a file or directory exists inside the container.

  Returns `true` if the path exists, `false` otherwise.
  """
  @spec exists?(container_ref(), String.t(), keyword()) :: boolean()
  def exists?(container, path, opts \\ []) do
    case exec(container, ["test", "-e", path], opts) do
      {:ok, ""} -> true
      _ -> false
    end
  end

  # ── Directory listing ─────────────────────────────────────────────

  @doc """
  Lists the contents of a directory inside the container.

  Returns `{:ok, entries}` where `entries` is a list of file/directory names.

  ## Examples

      iex> DevTools.list_dir(container, "/app")
      {:ok, ["config.json", "lib", "mix.exs"]}
  """
  @spec list_dir(container_ref(), String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def list_dir(container, container_path, opts \\ []) do
    case exec(container, ["ls", "-1", container_path], opts) do
      {:ok, output} ->
        entries =
          output
          |> String.split("\n", trim: true)
          |> Enum.reject(&(&1 == ""))

        {:ok, entries}

      error ->
        error
    end
  end

  @doc """
  Lists directory contents with details (permissions, size, etc.).

  Returns `{:ok, entries}` where `entries` is a list of formatted strings.
  """
  @spec list_dir_long(container_ref(), String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def list_dir_long(container, container_path, opts \\ []) do
    case exec(container, ["ls", "-la", container_path], opts) do
      {:ok, output} ->
        entries =
          output
          |> String.split("\n", trim: true)
          |> Enum.drop(1)

        {:ok, entries}

      error ->
        error
    end
  end

  # ── Container info ────────────────────────────────────────────────

  @doc """
  Returns the running processes inside the container (like `ps aux`).

  ## Options

    * `:ps_args` — ps arguments (default: `"-ef"`)
  """
  @spec processes(container_ref(), keyword()) :: {:ok, map()} | {:error, term()}
  def processes(container, opts \\ []) do
    id = container_id(container)
    ps_args = Keyword.get(opts, :ps_args, "-ef")
    base_url = Keyword.get(opts, :base_url, default_url())
    Control.top(id, ps_args, base_url)
  end

  @doc """
  Returns live resource usage statistics for the container.

  ## Options

    * `:stream` — stream stats (default: `false`)
  """
  @spec stats(container_ref(), keyword()) :: {:ok, map()} | {:error, term()}
  def stats(container, opts \\ []) do
    id = container_id(container)
    base_url = Keyword.get(opts, :base_url, default_url())
    Control.stats(id, opts, base_url)
  end

  @doc """
  Returns the container's current state (running, paused, etc.).
  """
  @spec state(container_ref(), keyword()) :: {:ok, map()} | {:error, term()}
  def state(container, opts \\ []) do
    id = container_id(container)
    base_url = Keyword.get(opts, :base_url, default_url())
    Control.state(id, base_url)
  end

  @doc """
  Returns whether the container is currently running.
  """
  @spec running?(container_ref(), keyword()) :: boolean()
  def running?(container, opts \\ []) do
    id = container_id(container)
    base_url = Keyword.get(opts, :base_url, default_url())
    Control.running?(id, base_url)
  end

  # ── Private ───────────────────────────────────────────────────────

  defp container_id(%Config{container_id: id}) when is_binary(id), do: id
  defp container_id(id) when is_binary(id), do: id

  defp exec_opts(opts) do
    []
    |> then(fn acc -> if Keyword.get(opts, :tty), do: [{:tty, true} | acc], else: acc end)
    |> then(fn acc ->
      if dir = Keyword.get(opts, :workdir), do: [{:workdir, dir} | acc], else: acc
    end)
    |> then(fn acc ->
      if user = Keyword.get(opts, :user), do: [{:user, user} | acc], else: acc
    end)
    |> then(fn acc -> if env = Keyword.get(opts, :env), do: [{:env, env} | acc], else: acc end)
  end

  defp create_tar(filename, contents) do
    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}-#{filename}.tar"
      )

    :ok = :erl_tar.create(tmp_path, [{String.to_charlist(filename), contents}])

    case File.read(tmp_path) do
      {:ok, data} ->
        File.rm(tmp_path)
        data

      {:error, reason} ->
        File.rm(tmp_path)
        raise "Failed to read tar: #{inspect(reason)}"
    end
  end

  defp upload_tar_to_container(id, dest_path, tar_data, base_url) do
    client = Req.new()

    case Req.put(client,
           url: "#{base_url}/containers/#{id}/archive?path=#{dest_path}",
           body: tar_data,
           headers: [{"content-type", "application/x-tar"}]
         ) do
      {:ok, %{status: status}} when status in [200, 201] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_tar_to_host(tar_data, host_path) do
    case :erl_tar.extract({:binary, tar_data}, [:cwd, String.to_charlist(host_path)]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:tar_extract_failed, reason}}
    end
  end

  defp default_url do
    case System.get_env("CONTAINER_ENGINE_HOST") ||
           System.get_env("CONTAINER_HOST") ||
           System.get_env("DOCKER_HOST") do
      nil -> "http://d"
      "" -> "http://d"
      url when is_binary(url) -> TestcontainerEx.Connection.Url.construct(url)
    end
  end
end
