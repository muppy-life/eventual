defmodule Eventual.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :aggregate_id, :string, null: false
      add :aggregate_type, :string, null: false
      add :data, :map, null: false
      add :metadata, :map, null: false, default: fragment("'{}'::jsonb")
      add :sequence_number, :bigint
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(updated_at: false)
    end

    # Index for querying events by aggregate (most common query pattern)
    create index(:events, [:aggregate_type, :aggregate_id, :sequence_number])

    # Index for querying by event type
    create index(:events, [:event_type])

    # Index for querying by time range
    create index(:events, [:occurred_at])

    # Index for insertion order
    create index(:events, [:inserted_at])
  end
end
