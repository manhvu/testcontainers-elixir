defmodule TestcontainerEx.Constants do
  @moduledoc """
  Library metadata constants.

  This module delegates to `TestcontainerEx.Util.Constants` for static values
  and to `TestcontainerEx.Docker.Engine` for runtime engine detection.
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

  Returns `:docker`, `:podman`, or `:minikube`.
  Results are cached after the first call.
  """
  def container_engine do
    TestcontainerEx.Docker.Engine.detect()
  end

  @doc """
  Returns `true` when running in a minikube environment.
  """
  def minikube_env? do
    TestcontainerEx.Docker.Engine.minikube?()
  end
end
