defmodule TestcontainerEx.Retry do
  @moduledoc """
  Exponential-backoff retry for transient failures.

  Retries a function up to `max_attempts` times with exponential backoff
  and optional jitter. Useful for Docker API calls that may fail transiently
  (e.g. socket hiccups, Ryuk not ready, daemon under pressure).

  ## Example

      Retry.with_backoff(fn -> Docker.ping(conn) end, max_attempts: 5)
  """

  @doc """
  Retries `fun` up to `max_attempts` times with exponential backoff.

  Returns `{:ok, result}` on success or `{:error, last_error}` after all attempts fail.

  ## Options

  - `:base_ms` — initial wait in milliseconds (default: `200`)
  - `:max_ms` — maximum wait cap (default: `5_000`)
  - `:jitter` — add up to this many ms of random jitter (default: `100`)

  ## Example

      Retry.with_backoff(fn -> Docker.ping(conn) end, max_attempts: 5)
  """
  @spec with_backoff((-> {:ok, any()} | {:error, any()}), keyword()) ::
          {:ok, any()} | {:error, any()}
  def with_backoff(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_ms = Keyword.get(opts, :base_ms, 200)
    max_ms = Keyword.get(opts, :max_ms, 5_000)
    jitter = Keyword.get(opts, :jitter, 100)

    do_retry(fun, max_attempts, base_ms, max_ms, jitter, 1)
  end

  defp do_retry(fun, max, _base, _cap, _jitter, attempt) when attempt > max do
    fun.()
  end

  defp do_retry(fun, max, base, cap, jitter, attempt) do
    case fun.() do
      {:ok, _} = ok ->
        ok

      {:error, _} = err when attempt >= max ->
        err

      {:error, _} ->
        wait = min(round(base * :math.pow(2, attempt - 1)), cap) + :rand.uniform(jitter)
        Process.sleep(wait)
        do_retry(fun, max, base, cap, jitter, attempt + 1)
    end
  end
end
