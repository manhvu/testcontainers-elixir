---
name: stabilize-tests
description: Stabilize Docker-dependent ExUnit tests in testcontainer_ex. Use when asked to reduce flakiness, improve test reliability, or address environment-dependent failures in container lifecycle tests.
---

# Stabilize TestcontainerEx Tests

This skill provides concrete guidance for reducing environment-dependent flakiness in the `testcontainer_ex` test suite.

## Common Instability Patterns

### 1. Container Start Timeouts (most common)

**Symptom:** `ExUnit.TimeoutError` after 300_000ms during `start_container` or `setup`.

**Root cause:** Docker daemon under resource pressure (Colima on macOS, overloaded daemon, cold image pulls).

**Fixes (apply in order of preference):**

1. Increase the per-test timeout in `test/test_helper.exs` or in the failing test module:
   ```elixir
   @moduletag timeout: 600_000  # 10 minutes for slow machines
   ```
   Or per-test:
   ```elixir
   @tag timeout: 600_000
   test "creates and starts ceph container" do
   ```

2. Pre-pull images in `test/test_helper.exs` setup_all to avoid pull-during-test latency:
   ```elixir
   setup_all do
     TestcontainerEx.pull_image("nginx:alpine")
     TestcontainerEx.pull_image("mysql:8")
     :ok
   end
   ```

3. Add retry logic for transient Docker API errors (HTTP 500, econnrefused). The `Lifecycle` module already retries container creation and start. Extend `start_and_wait/4` to retry the full `create_and_start` sequence on `{:http_error, 500}`:
   ```elixir
   defp create_and_start(config, builder, conn, state, retries_left \\ 3)
   defp create_and_start(config, builder, conn, state, 0), do: do_create_and_start(config, builder, conn, state)
   defp create_and_start(config, builder, conn, state, retries_left) do
     case do_create_and_start(config, builder, conn, state) do
       {:error, {:http_error, 500}} ->
         Logger.warning("Retrying container creation after HTTP 500, #{retries_left} retries left")
         :timer.sleep(2000)
         create_and_start(config, builder, conn, state, retries_left - 1)
       other -> other
     end
   end
   ```

### 2. Wait Strategy Timeouts

**Symptom:** `WithClauseError` on `{:error, %Error{code: :wait_strategy_failed, ...}}` in `start_and_wait/4`.

**Root cause:** Container starts but the wait condition (HTTP check, log pattern, command check) times out because the container is slow to initialize.

**Fixes:**

1. Increase wait strategy timeouts in container `new/0` or test setup:
   ```elixir
   # In HttpWaitStrategy
   HttpWaitStrategy.new("/", port, timeout: 15_000, max_retries: 3)

   # In CommandWaitStrategy
   CommandWaitStrategy.new(["nodetool", "status"], timeout: 180_000)
   ```

2. For `HttpWaitStrategy`, increase `max_retries` rather than just `timeout` — gives the container more chances:
   ```elixir
   HttpWaitStrategy.new("/", port, timeout: 5000, max_retries: 5)
   ```

3. For `CommandWaitStrategy`, increase `retry_delay` to give the container more breathing room between checks:
   ```elixir
   CommandWaitStrategy.new(["nodetool", "status"], timeout: 120_000, retry_delay: 1000)
   ```

### 3. Port Conflicts and Socket Errors

**Symptom:** `socket closed`, `connection refused`, `tcp recv: unknown POSIX error: closed`.

**Root cause:** Container exposes a port but the host-side socket isn't ready yet, or Ryuk reaper interferes.

**Fixes:**

1. Ensure `HttpWaitStrategy` waits on the correct port and path before tests make requests.

2. Add a small `Process.sleep/1` after `start_container` returns in tests that immediately make HTTP requests (belt-and-suspenders beyond the wait strategy):
   ```elixir
   {:ok, container} = TestcontainerEx.start_container(config)
   Process.sleep(500)  # let the socket fully bind
   ```

3. For tests that use `nginx:alpine` as a generic HTTP target, increase the wait strategy retries:
   ```elixir
   |> Config.with_waiting_strategy(HttpWaitStrategy.new("/", port, timeout: 5000, max_retries: 3))
   ```

### 4. Docker Daemon 500 Errors

**Symptom:** `{:error, {:http_error, 500}}` from Docker API calls.

**Root cause:** Colima/Docker daemon transient failures, especially under concurrent load.

**Fixes:**

1. The `Lifecycle` module retries container creation and start on HTTP 500. Extend this to image pull:
   ```elixir
   defp pull_with_fallback(config, conn, retries_left \\ 3)
   defp pull_with_fallback(config, conn, 0), do: do_pull_with_fallback(config, conn)
   defp pull_with_fallback(config, conn, retries_left) do
     case do_pull_with_fallback(config, conn) do
       {:error, {:http_error, 500}} ->
         Logger.warning("Retrying image pull after HTTP 500, #{retries_left} retries left")
         :timer.sleep(2000)
         pull_with_fallback(config, conn, retries_left - 1)
       other -> other
     end
   end
   ```

2. Serialize test startup with `async: false` for tests that all hit the same daemon (already done in some modules).

### 5. Container Reuse for Heavy Images

**Symptom:** Tests that start heavy containers (MySQL, Scylla, Ceph) are slow and flaky.

**Fix:** Enable reuse for these containers in test setup:
```elixir
config = %MySqlContainer{image: "mysql:8", ..., reuse: true}
```
Combined with a `setup_all` that pre-creates the reusable container, this avoids per-test startup cost.

## Application Checklist

When asked to stabilize tests, apply these changes:

1. **`lib/testcontainer_ex/container/lifecycle.ex`** — Add retry logic to `maybe_pull_image/2` for HTTP 500 errors (mirrors existing retry in `create_container_with_retry/3`).

2. **`test/test_helper.exs`** — Add `setup_all` block that pre-pulls commonly used images (`nginx:alpine`, `mysql:8`, `redis:latest`).

3. **Per slow test module** — Add `@moduletag timeout: 600_000` to modules that start heavy containers (Ceph, Scylla, MySQL, Elixir distribution).

4. **Wait strategies** — Increase `max_retries` on `HttpWaitStrategy` in tests that hit HTTP endpoints immediately after start.

5. **Do NOT change:**
   - Test assertions (if these are wrong, fix the source, not the test)
   - `async: true` to `async: false` globally (only per-module, and only if tests share state)
   - Source code behavior to match tests (fix tests to match source)
