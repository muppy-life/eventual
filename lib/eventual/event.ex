defmodule Eventual.Event do
  @moduledoc """
  Schema for storing events in the event store.

  Events represent domain events that have occurred in the system.
  They are immutable and append-only - no updates or deletes are allowed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          event_type: String.t() | nil,
          aggregate_id: String.t() | nil,
          aggregate_type: String.t() | nil,
          data: map() | nil,
          metadata: map() | nil,
          sequence_number: integer() | nil,
          occurred_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "events" do
    field :event_type, :string
    field :aggregate_id, :string
    field :aggregate_type, :string
    field :data, :map
    field :metadata, :map
    field :sequence_number, :integer
    field :occurred_at, :utc_datetime_usec

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for creating a new event.

  ## Required fields
  - `:event_type` - Type of event (e.g., "user.created")
  - `:aggregate_id` - ID of the entity this event relates to
  - `:aggregate_type` - Type of entity (e.g., "User", "Order")
  - `:data` - Event payload

  ## Optional fields
  - `:metadata` - Additional context (defaults to empty map)
  - `:occurred_at` - When the event occurred (defaults to current time)
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event_type,
      :aggregate_id,
      :aggregate_type,
      :data,
      :metadata,
      :sequence_number,
      :occurred_at
    ])
    |> validate_required([:event_type, :aggregate_id, :aggregate_type, :data])
    |> put_default_metadata()
    |> put_default_occurred_at()
  end

  defp put_default_metadata(changeset) do
    case get_change(changeset, :metadata) do
      nil -> put_change(changeset, :metadata, %{})
      _ -> changeset
    end
  end

  defp put_default_occurred_at(changeset) do
    case get_change(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
