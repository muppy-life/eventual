defmodule Eventual.Application do
  @moduledoc """
  OTP Application for Eventual event store.

  Starts and supervises the Eventual.Repo database connection.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Eventual.Repo
    ]

    opts = [strategy: :one_for_one, name: Eventual.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
