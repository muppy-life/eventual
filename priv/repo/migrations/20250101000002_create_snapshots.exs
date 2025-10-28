defmodule Eventual.Repo.Migrations.CreateSnapshots do
  use Ecto.Migration

  def change do
    create table(:snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :aggregate_id, :string, null: false
      add :aggregate_type, :string, null: false
      add :data, :map, null: false
      add :sequence_number, :bigint, null: false
      add :metadata, :map, null: false, default: fragment("'{}'::jsonb")

      timestamps(updated_at: false)
    end

    # Unique constraint to prevent duplicate snapshots at same sequence number
    # This also serves as an index for querying latest snapshot
    create unique_index(:snapshots, [:aggregate_type, :aggregate_id, :sequence_number])
  end
end
