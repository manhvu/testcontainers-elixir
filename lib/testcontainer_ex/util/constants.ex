defmodule TestcontainerEx.Util.Constants do
  @moduledoc """
  Library metadata constants.
  """

  def library_name, do: :testcontainer_ex
  def library_version, do: "2.3.1"
  def ryuk_version, do: "0.14.0"
  def container_label, do: "org.testcontainer_ex"
  def container_lang_label, do: "org.testcontainer_ex.lang"
  def container_reuse_hash_label, do: "org.testcontainer_ex.reuse-hash"
  def container_reuse, do: "org.testcontainer_ex.reuse"
  def container_lang_value, do: Elixir |> Atom.to_string() |> String.downcase()
  def container_session_id_label, do: "org.testcontainer_ex.session-id"
  def container_version_label, do: "org.testcontainer_ex.version"
  def user_agent, do: "tc-elixir/" <> __MODULE__.library_version()
end
