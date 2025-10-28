defmodule Eventual.Snapshot do
  @moduledoc """
  Schema for storing aggregate snapshots in the event store.

  Snapshots represent the computed state of an aggregate at a specific point in time,
  allowing for efficient state reconstruction without replaying all events.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          aggregate_id: String.t() | nil,
          aggregate_type: String.t() | nil,
          data: map() | nil,
          sequence_number: integer() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "snapshots" do
    field :aggregate_id, :string
    field :aggregate_type, :string
    field :data, :map
    field :sequence_number, :integer
    field :metadata, :map

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for creating a new snapshot.

  ## Required fields
  - `:aggregate_id` - ID of the entity
  - `:aggregate_type` - Type of entity (e.g., "User", "Order")
  - `:data` - Computed state at this point
  - `:sequence_number` - Last event sequence number included in this snapshot

  ## Optional fields
  - `:metadata` - Additional snapshot metadata (defaults to empty map)
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :aggregate_id,
      :aggregate_type,
      :data,
      :sequence_number,
      :metadata
    ])
    |> validate_required([:aggregate_id, :aggregate_type, :data, :sequence_number])
    |> validate_number(:sequence_number, greater_than: 0)
    |> put_default_metadata()
    |> unique_constraint([:aggregate_type, :aggregate_id, :sequence_number],
      name: :snapshots_aggregate_type_aggregate_id_sequence_number_index
    )
  end

  defp put_default_metadata(changeset) do
    case get_change(changeset, :metadata) do
      nil -> put_change(changeset, :metadata, %{})
      _ -> changeset
    end
  end
end
