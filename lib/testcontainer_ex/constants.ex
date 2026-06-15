defmodule TestcontainerEx.Constants do
  @moduledoc """
  Library metadata constants.

  This module delegates to `TestcontainerEx.Util.Constants` for static values
  and to `TestcontainerEx.Engine` for runtime engine detection.
  """

  # ── Delegates to Util.Constants ──────────────────────────────────

  defdelegate library_name, to: TestcontainerEx.Util.Constants
  defdelegate library_version, to: TestcontainerEx.Util.Constants
  defdelegate ryuk_version, to: TestcontainerEx.Util.Constants
  defdelegate container_label, to: TestcontainerEx.Util.Constants
  defdelegate container_lang_label, to: TestcontainerEx.Util.Constants
  defdelegate container_reuse_hash_label, to: TestcontainerEx.Util.Constants
  defdelegate container_reuse, to: TestcontainerEx.Util.Constants
  defdelegate container_lang_value, to: TestcontainerEx.Util.Constants
  defdelegate container_session_id_label, to: TestcontainerEx.Util.Constants
  defdelegate container_version_label, to: TestcontainerEx.Util.Constants
  defdelegate user_agent, to: TestcontainerEx.Util.Constants

  # ── Runtime engine detection ──────────────────────────────────────

  @doc """
  Detects which container engine is in use.

  Returns `:docker`, `:podman`, `:minikube`, `:colima`, or `:apple_container`.

  Resolution order:
  1. Runtime override set via `TestcontainerEx.set_engine/1` (per-process)
  2. `CONTAINER_ENGINE` env var
  3. Auto-detection (cached in `:persistent_term` after first call)

  See `TestcontainerEx` for details on engine selection precedence.
  """
  def container_engine do
    TestcontainerEx.Engine.detect()
  end

  @doc """
  Returns `true` when running in a minikube environment.
  """
  def minikube_env? do
    TestcontainerEx.Engine.minikube?()
  end
end
