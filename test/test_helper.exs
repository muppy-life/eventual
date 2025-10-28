# Start the Repo for testing
{:ok, _} = Application.ensure_all_started(:eventual)

# Use sandbox mode for concurrent tests
Ecto.Adapters.SQL.Sandbox.mode(Eventual.Repo, :manual)

ExUnit.start()
