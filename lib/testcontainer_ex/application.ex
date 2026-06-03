defmodule TestcontainerEx.Application do
  @moduledoc """
  Application callback for TestcontainerEx.

  Starts the TestcontainerEx GenServer as part of the supervision tree.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {TestcontainerEx.Server, name: TestcontainerEx}
    ]

    opts = [strategy: :one_for_one, name: TestcontainerEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
