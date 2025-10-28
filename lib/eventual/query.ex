defmodule Eventual.Query do
  @moduledoc """
  Query builder functions for filtering events and snapshots.
  """

  import Ecto.Query
  alias Eventual.{Event, Snapshot}

  @doc """
  Builds a query for events with optional filters.

  ## Options
  - `:event_type` - Filter by event type
  - `:aggregate_type` - Filter by aggregate type
  - `:aggregate_id` - Filter by aggregate ID
  - `:from` - Events occurring after this datetime
  - `:to` - Events occurring before this datetime
  - `:limit` - Limit number of results
  - `:order_by` - Order by field (default: :sequence_number or :occurred_at)
  """
  @spec events(keyword()) :: Ecto.Query.t()
  def events(filters \\ []) do
    Event
    |> apply_event_filters(filters)
    |> apply_ordering(filters)
    |> apply_limit(filters)
  end

  @doc """
  Builds a query for events of a specific aggregate.
  """
  @spec aggregate_events(String.t(), String.t(), keyword()) :: Ecto.Query.t()
  def aggregate_events(aggregate_type, aggregate_id, opts \\ []) do
    query = from e in Event,
      where: e.aggregate_type == ^aggregate_type,
      where: e.aggregate_id == ^aggregate_id,
      order_by: [asc: e.sequence_number]

    query
    |> apply_sequence_filter(opts)
    |> apply_limit(opts)
  end

  @doc """
  Builds a query to get events after a specific sequence number.
  """
  @spec events_after_sequence(String.t(), String.t(), integer()) :: Ecto.Query.t()
  def events_after_sequence(aggregate_type, aggregate_id, sequence_number) do
    from e in Event,
      where: e.aggregate_type == ^aggregate_type,
      where: e.aggregate_id == ^aggregate_id,
      where: e.sequence_number > ^sequence_number,
      order_by: [asc: e.sequence_number]
  end

  @doc """
  Builds a query for the latest snapshot of an aggregate.
  """
  @spec latest_snapshot(String.t(), String.t()) :: Ecto.Query.t()
  def latest_snapshot(aggregate_type, aggregate_id) do
    from s in Snapshot,
      where: s.aggregate_type == ^aggregate_type,
      where: s.aggregate_id == ^aggregate_id,
      order_by: [desc: s.sequence_number],
      limit: 1
  end

  @doc """
  Builds a query for a snapshot at a specific sequence number.
  """
  @spec snapshot_at(String.t(), String.t(), integer()) :: Ecto.Query.t()
  def snapshot_at(aggregate_type, aggregate_id, sequence_number) do
    from s in Snapshot,
      where: s.aggregate_type == ^aggregate_type,
      where: s.aggregate_id == ^aggregate_id,
      where: s.sequence_number == ^sequence_number
  end

  @doc """
  Builds a query for all snapshots of an aggregate.
  """
  @spec aggregate_snapshots(String.t(), String.t(), keyword()) :: Ecto.Query.t()
  def aggregate_snapshots(aggregate_type, aggregate_id, opts \\ []) do
    query = from s in Snapshot,
      where: s.aggregate_type == ^aggregate_type,
      where: s.aggregate_id == ^aggregate_id,
      order_by: [desc: s.sequence_number]

    query
    |> apply_limit(opts)
  end

  # Private helpers

  defp apply_event_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:event_type, type}, q ->
        from e in q, where: e.event_type == ^type

      {:aggregate_type, type}, q ->
        from e in q, where: e.aggregate_type == ^type

      {:aggregate_id, id}, q ->
        from e in q, where: e.aggregate_id == ^id

      {:from, datetime}, q ->
        from e in q, where: e.occurred_at >= ^datetime

      {:to, datetime}, q ->
        from e in q, where: e.occurred_at <= ^datetime

      _other, q ->
        q
    end)
  end

  defp apply_sequence_filter(query, opts) do
    case Keyword.get(opts, :from_sequence) do
      nil -> query
      seq -> from e in query, where: e.sequence_number > ^seq
    end
  end

  defp apply_ordering(query, filters) do
    case Keyword.get(filters, :order_by) do
      :sequence_number -> from e in query, order_by: [asc: e.sequence_number]
      :occurred_at -> from e in query, order_by: [asc: e.occurred_at]
      :inserted_at -> from e in query, order_by: [asc: e.inserted_at]
      nil -> from e in query, order_by: [asc: e.inserted_at]
      _ -> query
    end
  end

  defp apply_limit(query, opts) do
    case Keyword.get(opts, :limit) do
      nil -> query
      limit -> from q in query, limit: ^limit
    end
  end
end
