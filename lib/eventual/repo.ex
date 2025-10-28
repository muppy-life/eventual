defmodule Eventual.Repo do
  @moduledoc """
  Ecto repository for the Eventual event store.

  This repository manages the database connection for storing events and snapshots,
  separate from the host application's database.
  """

  use Ecto.Repo,
    otp_app: :eventual,
    adapter: Ecto.Adapters.Postgres
end
