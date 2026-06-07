defmodule TestcontainerEx.Log do
  @moduledoc """
  Structured logging convenience for TestcontainerEx.

  Wraps Elixir's `Logger` with contextual metadata (container ID, image,
  session, engine) so log lines are easy to filter and correlate.

  ## Usage

      # Inside container lifecycle code:
      import TestcontainerEx.Log

      log_info("Container started", container_id: id, image: img)
      log_debug("Pulling image", image: img)
      log_warning("Ryuk disabled", reason: :config)

  ## Configuration

  All functions respect the standard `:logger` configuration.
  The metadata keys `:testcontainer_ex`, `:container_id`, and `:image`
  are automatically included when provided.
  """

  require Logger

  @doc """
  Logs an informational message with optional TestcontainerEx metadata.

  ## Examples

      log_info("Container started", container_id: "abc123", image: "postgres:15")
  """
  @spec info(String.t(), keyword()) :: :ok
  def info(message, meta \\ []) do
    Logger.info(message, build_meta(meta))
  end

  @doc """
  Logs a debug message with optional TestcontainerEx metadata.

  ## Examples

      log_debug("Pulling image", image: "redis:7")
  """
  @spec debug(String.t(), keyword()) :: :ok
  def debug(message, meta \\ []) do
    Logger.debug(message, build_meta(meta))
  end

  @doc """
  Logs a warning message with optional TestcontainerEx metadata.

  ## Examples

      log_warning("Ryuk disabled — containers will not auto-clean", reason: :config)
  """
  @spec warning(String.t(), keyword()) :: :ok
  def warning(message, meta \\ []) do
    Logger.warning(message, build_meta(meta))
  end

  @doc """
  Logs an error message with optional TestcontainerEx metadata.

  ## Examples

      log_error("Failed to start container", container_id: id, error: reason)
  """
  @spec error(String.t(), keyword()) :: :ok
  def error(message, meta \\ []) do
    Logger.error(message, build_meta(meta))
  end

  @doc """
  Logs a message at the given level with optional TestcontainerEx metadata.
  """
  @spec log(Logger.level(), String.t(), keyword()) :: :ok
  def log(level, message, meta \\ []) do
    Logger.log(level, message, build_meta(meta))
  end

  # ── Private ───────────────────────────────────────────────────────

  defp build_meta(meta) when is_list(meta) do
    base = [testcontainer_ex: true]

    base =
      case Keyword.get(meta, :container_id) do
        nil -> base
        id -> Keyword.put(base, :container_id, id)
      end

    base =
      case Keyword.get(meta, :image) do
        nil -> base
        img -> Keyword.put(base, :image, img)
      end

    base =
      case Keyword.get(meta, :session_id) do
        nil -> base
        sid -> Keyword.put(base, :session_id, sid)
      end

    base =
      case Keyword.get(meta, :engine) do
        nil -> base
        eng -> Keyword.put(base, :engine, eng)
      end

    # Include any extra keys the caller passed
    extra =
      meta
      |> Keyword.drop([:container_id, :image, :session_id, :engine])

    Keyword.merge(base, extra)
  end
end
