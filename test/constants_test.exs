defmodule TestcontainerEx.ConstantsTest do
  use ExUnit.Case, async: true

  test "have correct values" do
    assert TestcontainerEx.Constants.container_label() == "org.testcontainer_ex"

    assert TestcontainerEx.Constants.container_session_id_label() ==
             "org.testcontainer_ex.session-id"

    assert TestcontainerEx.Constants.container_reuse_hash_label() ==
             "org.testcontainer_ex.reuse-hash"

    assert TestcontainerEx.Constants.container_reuse() == "org.testcontainer_ex.reuse"
    assert TestcontainerEx.Constants.container_version_label() == "org.testcontainer_ex.version"
    assert is_binary(TestcontainerEx.Constants.library_version())
    assert is_atom(TestcontainerEx.Constants.library_name())
  end
end
