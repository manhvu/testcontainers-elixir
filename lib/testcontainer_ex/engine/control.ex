# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Engine.Control do
  @moduledoc """
  Low-level container control operations via the Docker Engine API.

  These functions talk directly to the Docker Engine API and work with
  raw container IDs. They are useful for fine-grained control beyond
  what the high-level `TestcontainerEx` API provides.

  All functions accept an optional `base_url` parameter. When omitted,
  the URL is derived from `CONTAINER_ENGINE_HOST`,
  or defaults to `http://d`.

  ## Usage

      # Pause a container
      :ok = TestcontainerEx.Engine.Control.pause("abc123")

      # Get live resource stats
      stats = TestcontainerEx.Engine.Control.stats("abc123")

      # Upload a file
      :ok = TestcontainerEx.Engine.Control.upload("abc123", "/app/config.yml", "config.yml")

      # Download a file
      {:ok, data} = TestcontainerEx.Engine.Control.download("abc123", "/app/data.json")

      # Commit container to a new image
      {:ok, image_id} = TestcontainerEx.Engine.Control.commit("abc123", "my-snapshot:v1")
  """

  alias TestcontainerEx.Connection.Url

  # ── Lifecycle controls ────────────────────────────────────────────

  @doc "Starts a stopped container."
  @spec start(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def start(container_id, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.post(client, url: "#{url}/containers/#{container_id}/start", body: "") do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{status: 304}} -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stops a running container. Optional `t` parameter for timeout in seconds."
  @spec stop(String.t(), integer() | nil, String.t() | nil) :: :ok | {:error, term()}
  def stop(container_id, timeout \\ nil, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()
    query = if timeout, do: "?t=#{timeout}", else: ""

    case Req.post(client, url: "#{url}/containers/#{container_id}/stop#{query}", body: "") do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{status: 304}} -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Restarts a running container. Optional `t` parameter for timeout in seconds."
  @spec restart(String.t(), integer() | nil, String.t() | nil) :: :ok | {:error, term()}
  def restart(container_id, timeout \\ nil, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()
    query = if timeout, do: "?t=#{timeout}", else: ""

    case Req.post(client, url: "#{url}/containers/#{container_id}/restart#{query}", body: "") do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Kills a running container with the given signal (default: SIGKILL)."
  @spec kill(String.t(), String.t(), String.t() | nil) :: :ok | {:error, term()}
  def kill(container_id, signal \\ "SIGKILL", base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.post(client, url: "#{url}/containers/#{container_id}/kill?signal=#{signal}", body: "") do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Pauses a running container."
  @spec pause(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def pause(container_id, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.post(client, url: "#{url}/containers/#{container_id}/pause", body: "") do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Unpauses a paused container."
  @spec unpause(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def unpause(container_id, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.post(client, url: "#{url}/containers/#{container_id}/unpause", body: "") do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Removes a container. Options: `:force`, `:remove_volumes`."
  @spec remove(String.t(), keyword(), String.t() | nil) :: :ok | {:error, term()}
  def remove(container_id, opts \\ [], base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    query =
      []
      |> then(fn acc -> if Keyword.get(opts, :force), do: ["force=true" | acc], else: acc end)
      |> then(fn acc ->
        if Keyword.get(opts, :remove_volumes), do: ["v=true" | acc], else: acc
      end)
      |> then(fn
        [] -> ""
        parts -> "?" <> Enum.join(parts, "&")
      end)

    case Req.delete(client, url: "#{url}/containers/#{container_id}#{query}") do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Renames a container."
  @spec rename(String.t(), String.t(), String.t() | nil) :: :ok | {:error, term()}
  def rename(container_id, new_name, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.post(client, url: "#{url}/containers/#{container_id}/rename?name=#{new_name}", body: "") do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Updates container resources (memory, CPU, etc.)."
  @spec update(String.t(), keyword(), String.t() | nil) :: :ok | {:error, term()}
  def update(container_id, opts \\ [], base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    body = build_update_body(opts)

    case Req.post(client, url: "#{url}/containers/#{container_id}/update", body: body) do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_update_body(opts) do
    %{}
    |> maybe_put("Memory", Keyword.get(opts, :memory))
    |> maybe_put("MemorySwap", Keyword.get(opts, :memory_swap))
    |> maybe_put("MemoryReservation", Keyword.get(opts, :memory_reservation))
    |> maybe_put("NanoCpus", Keyword.get(opts, :nano_cpus))
    |> maybe_put("CpuShares", Keyword.get(opts, :cpu_shares))
    |> maybe_put("CpuPeriod", Keyword.get(opts, :cpu_period))
    |> maybe_put("CpuQuota", Keyword.get(opts, :cpu_quota))
    |> maybe_put("CpusetCpus", Keyword.get(opts, :cpuset_cpus))
    |> maybe_put("CpusetMems", Keyword.get(opts, :cpuset_mems))
    |> maybe_put("PidsLimit", Keyword.get(opts, :pids_limit))
    |> maybe_put("RestartPolicy", format_restart_policy(Keyword.get(opts, :restart_policy)))
    |> Jason.encode!()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_restart_policy(nil), do: nil
  defp format_restart_policy(policy) when is_binary(policy), do: %{"Name" => policy}
  defp format_restart_policy(%{} = policy), do: policy

  # ── Container creation & inspection ───────────────────────────────

  @doc "Creates a container from a config map. Returns `{:ok, container_id}`."
  @spec create(map(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def create(config, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    body = Jason.encode!(config)

    case Req.post(client, url: "#{url}/containers/create", body: body, headers: [{"content-type", "application/json"}]) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        case Jason.decode(body) do
          {:ok, %{"Id" => id}} -> {:ok, id}
          {:ok, _} -> {:error, {:no_container_id, body}}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Creates a container with a specific name."
  @spec create_named(String.t(), map(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def create_named(name, config, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    body = Jason.encode!(config)

    case Req.post(client, url: "#{url}/containers/create?name=#{name}", body: body, headers: [{"content-type", "application/json"}]) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        case Jason.decode(body) do
          {:ok, %{"Id" => id}} -> {:ok, id}
          {:ok, _} -> {:error, {:no_container_id, body}}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns detailed container inspection."
  @spec inspect_container(String.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def inspect_container(container_id, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/containers/#{container_id}/json") do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns container state (running, paused, etc.)."
  @spec state(String.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  @dialyzer {:no_match, state: 2}
  def state(container_id, base_url \\ "") do
    base_url = if base_url == "", do: nil, else: base_url

    case inspect(container_id, base_url) do
      {:ok, info} -> {:ok, Map.get(info, "State", %{})}
      error -> error
    end
  end

  @doc "Returns whether the container is running."
  @spec running?(String.t(), String.t() | nil) :: boolean()
  @dialyzer {:no_match, running?: 2}
  def running?(container_id, base_url \\ "") do
    base_url = if base_url == "", do: nil, else: base_url

    case state(container_id, base_url) do
      {:ok, %{"Running" => true}} -> true
      _ -> false
    end
  end

  @doc "Waits for a container to finish and returns its exit code."
  @spec wait(String.t(), String.t() | nil) :: {:ok, integer()} | {:error, term()}
  def wait(container_id, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.post(client, url: "#{url}/containers/#{container_id}/wait", body: "", receive_timeout: :infinity) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"StatusCode" => code}} -> {:ok, code}
          {:ok, _} -> {:error, {:unexpected_response, body}}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Logs ──────────────────────────────────────────────────────────

  @doc """
  Fetches container logs.

  Options:
    * `:stdout` — include stdout (default: true)
    * `:stderr` — include stderr (default: true)
    * `:timestamps` — include timestamps (default: false)
    * `:follow` — stream logs (default: false)
    * `:tail` — number of lines from end (default: "all")
    * `:since` — UNIX timestamp for logs since
    * `:until` — UNIX timestamp for logs until
  """
  @spec logs(String.t(), keyword(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def logs(container_id, opts \\ [], base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    query =
      [
        {"stdout", to_string(Keyword.get(opts, :stdout, true))},
        {"stderr", to_string(Keyword.get(opts, :stderr, true))},
        {"timestamps", to_string(Keyword.get(opts, :timestamps, false))},
        {"follow", to_string(Keyword.get(opts, :follow, false))},
        {"tail", Keyword.get(opts, :tail, "all")},
        {"since", if(s = Keyword.get(opts, :since), do: to_string(s), else: "")},
        {"until", if(u = Keyword.get(opts, :until), do: to_string(u), else: "")}
      ]
      |> Enum.reject(fn {_, v} -> v == "" end)
      |> URI.encode_query()

    case Req.get(client, url: "#{url}/containers/#{container_id}/logs?#{query}") do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Exec ──────────────────────────────────────────────────────────

  @doc "Creates an exec instance inside a container."
  @spec create_exec(String.t(), [String.t()], keyword(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def create_exec(container_id, command, opts \\ [], base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    body =
      %{
        "Cmd" => command,
        "AttachStdout" => Keyword.get(opts, :attach_stdout, true),
        "AttachStderr" => Keyword.get(opts, :attach_stderr, true),
        "AttachStdin" => Keyword.get(opts, :attach_stdin, false),
        "Tty" => Keyword.get(opts, :tty, false),
        "Env" => Keyword.get(opts, :env, []),
        "WorkingDir" => Keyword.get(opts, :workdir),
        "User" => Keyword.get(opts, :user)
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()
      |> Jason.encode!()

    case Req.post(client, url: "#{url}/containers/#{container_id}/exec", body: body, headers: [{"content-type", "application/json"}]) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        case Jason.decode(body) do
          {:ok, %{"Id" => id}} -> {:ok, id}
          {:ok, _} -> {:error, {:no_exec_id, body}}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Starts a previously created exec instance."
  @spec start_exec(String.t(), keyword(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def start_exec(exec_id, opts \\ [], base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    body =
      %{
        "Detach" => Keyword.get(opts, :detach, false),
        "Tty" => Keyword.get(opts, :tty, false)
      }
      |> Jason.encode!()

    case Req.post(client, url: "#{url}/exec/#{exec_id}/start", body: body, headers: [{"content-type", "application/json"}]) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} when is_reference(body) -> {:ok, body}
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Inspects an exec instance."
  @spec inspect_exec(String.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def inspect_exec(exec_id, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/exec/#{exec_id}/json") do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Resizes an exec TTY."
  @spec resize_exec(String.t(), integer(), integer(), String.t() | nil) :: :ok | {:error, term()}
  def resize_exec(exec_id, width, height, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.post(client, url: "#{url}/exec/#{exec_id}/resize?h=#{height}&w=#{width}", body: "") do
      {:ok, %{status: status}} when status in [200, 201] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Stats & processes ─────────────────────────────────────────────

  @doc """
  Returns live resource usage statistics.

  Options:
    * `:stream` — stream stats (default: true)
  """
  @spec stats(String.t(), keyword(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def stats(container_id, opts \\ [], base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    stream = Keyword.get(opts, :stream, true)
    query = "stream=#{to_string(stream)}&one-shot=#{to_string(not stream)}"

    case Req.get(client, url: "#{url}/containers/#{container_id}/stats?#{query}") do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns running processes inside the container."
  @spec top(String.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def top(container_id, ps_args \\ "-ef", base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/containers/#{container_id}/top?ps_args=#{ps_args}") do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── File operations ───────────────────────────────────────────────

  @doc """
  Uploads a file to a container.

  The `source` can be:
  - A file path (string) — the file is read and uploaded
  - A binary — uploaded directly as the file contents
  """
  @spec upload(String.t(), String.t(), String.t() | binary(), String.t() | nil) ::
          :ok | {:error, term()}
  def upload(container_id, container_path, source, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    {tar_data, upload_path} =
      case source do
        path when is_binary(path) and byte_size(path) > 0 ->
          case File.stat(path) do
            {:ok, %{type: :regular}} ->
              filename = Path.basename(path)
              {create_tar_from_file(path), Path.join(container_path, filename)}

            _ ->
              # Treat as binary contents
              filename = Path.basename(container_path)
              {create_tar_from_binary(filename, path), container_path}
          end

        binary when is_binary(binary) ->
          filename = Path.basename(container_path)
          {create_tar_from_binary(filename, binary), container_path}
      end

    case Req.put(client, url: "#{url}/containers/#{container_id}/archive?path=#{upload_path}", body: tar_data, headers: [{"content-type", "application/x-tar"}]) do
      {:ok, %{status: status}} when status in [200, 201] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Downloads a file from a container as binary data."
  @spec download(String.t(), String.t(), String.t() | nil) :: {:ok, binary()} | {:error, term()}
  def download(container_id, container_path, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/containers/#{container_id}/archive?path=#{container_path}") do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Downloads and extracts a single file from a container archive."
  @spec download_file(String.t(), String.t(), String.t() | nil) ::
          {:ok, binary()} | {:error, term()}
  def download_file(container_id, container_path, base_url \\ nil) do
    case download(container_id, container_path, base_url) do
      {:ok, tar_data} ->
        case extract_first_file(tar_data) do
          {:ok, contents} -> {:ok, contents}
          {:error, reason} -> {:error, reason}
        end

      error ->
        error
    end
  end

  defp extract_first_file(tar_data) do
    case :erl_tar.extract({:binary, tar_data}, [:memory]) do
      {:ok, [{_name, contents}]} -> {:ok, contents}
      {:ok, []} -> {:error, :empty_archive}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_tar_from_file(path) do
    case File.read(path) do
      {:ok, contents} -> create_tar_from_binary(Path.basename(path), contents)
      {:error, reason} -> raise "Failed to read file: #{inspect(reason)}"
    end
  end

  defp create_tar_from_binary(filename, contents) do
    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}-#{filename}.tar"
      )

    :ok = :erl_tar.create(tmp_path, [{String.to_charlist(filename), contents}], [:compressed])

    case File.read(tmp_path) do
      {:ok, data} ->
        File.rm(tmp_path)
        data

      {:error, reason} ->
        File.rm(tmp_path)
        raise "Failed to read tar: #{inspect(reason)}"
    end
  end

  # ── Image operations ──────────────────────────────────────────────

  @doc "Commits a container to a new image."
  @spec commit(String.t(), String.t(), keyword(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def commit(container_id, repo_tag, opts \\ [], base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    body =
      %{
        "pause" => Keyword.get(opts, :pause, true),
        "comment" => Keyword.get(opts, :comment),
        "author" => Keyword.get(opts, :author),
        "changes" => Keyword.get(opts, :changes)
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()
      |> Jason.encode!()

    [repo, tag] = String.split(repo_tag, ":", parts: 2)
    query = "repo=#{repo}&tag=#{tag || "latest"}"

    case Req.post(client, url: "#{url}/commit?#{query}#{container_id}", body: body, headers: [{"content-type", "application/json"}]) do
      {:ok, %{status: 201, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"Id" => id}} -> {:ok, id}
          {:ok, _} -> {:error, {:no_image_id, body}}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Exports a container filesystem as a tarball."
  @spec export(String.t(), String.t() | nil) :: {:ok, binary()} | {:error, term()}
  def export(container_id, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/containers/#{container_id}/export") do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Resize TTY ────────────────────────────────────────────────────

  @doc "Resizes a container TTY."
  @spec resize(String.t(), integer(), integer(), String.t() | nil) :: :ok | {:error, term()}
  def resize(container_id, width, height, base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    case Req.post(client, url: "#{url}/containers/#{container_id}/resize?h=#{height}&w=#{width}", body: "") do
      {:ok, %{status: status}} when status in [200, 201] -> :ok
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Attach ────────────────────────────────────────────────────────

  @doc """
  Attaches to a container's streams.

  Returns `{:ok, reference()}` for streaming mode.
  """
  @spec attach(String.t(), keyword(), String.t() | nil) ::
          {:ok, binary() | reference()} | {:error, term()}
  def attach(container_id, opts \\ [], base_url \\ nil) do
    url = base_url || default_url()
    client = Req.new()

    query =
      [
        {"stream", to_string(Keyword.get(opts, :stream, true))},
        {"stdin", to_string(Keyword.get(opts, :stdin, false))},
        {"stdout", to_string(Keyword.get(opts, :stdout, true))},
        {"stderr", to_string(Keyword.get(opts, :stderr, true))},
        {"logs", to_string(Keyword.get(opts, :logs, false))}
      ]
      |> URI.encode_query()

    case Req.get(client, url: "#{url}/containers/#{container_id}/attach?#{query}", receive_timeout: :infinity) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} when is_reference(body) -> {:ok, body}
      {:ok, %{body: %{"message" => msg}}} -> {:error, msg}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Private ───────────────────────────────────────────────────────

  defp default_url do
    case System.get_env("CONTAINER_ENGINE_HOST") do
      nil -> "http://d"
      "" -> "http://d"
      url when is_binary(url) -> Url.construct(url)
    end
  end
end
