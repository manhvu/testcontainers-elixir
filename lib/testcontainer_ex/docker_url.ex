defmodule TestcontainerEx.DockerUrl do
  @moduledoc """
  Public alias for `TestcontainerEx.Connection.Url`.

  Keeps backward compatibility with code that references the flat module name.
  """

  alias TestcontainerEx.Connection.Url

  defdelegate construct(url), to: Url
  defdelegate tls_verify?, to: Url
  defdelegate https?(url), to: Url
end
