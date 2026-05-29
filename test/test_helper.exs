TestcontainerEx.start_link()

exclude =
  if TestcontainerEx.running_in_container?() do
    [:dood_limitation]
  else
    []
  end

ExUnit.start(timeout: 300_000, exclude: exclude)
