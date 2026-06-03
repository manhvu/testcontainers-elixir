defmodule TestcontainerEx.Connection.Strategies.Behaviour do
  @moduledoc """
  Protocol for resolving the container engine host URL.

  Each strategy attempts to find a reachable container engine.
  Strategies are tried in order until one succeeds.
  """
  @callback resolve() :: {:ok, String.t()} | {:error, term()}
end
