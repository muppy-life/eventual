defmodule Eventual do
  @moduledoc """
  Eventual - Event Store Client

  A library for persisting and retrieving domain events and snapshots.
  Provides a separate database connection for event storage, isolated from
  the host application's primary database.

  ## Event Operations

  Save events to the event store:

      Eventual.save_event("user.created", user_id, "User", %{name: "John"})
      Eventual.save_events([event1, event2, event3])

  Retrieve events:

      Eventual.get_event(event_id)
      Eventual.list_events(event_type: "user.created")
      Eventual.get_aggregate_events("User", user_id)
      Eventual.stream_events(aggregate_type: "Order")

  ## Snapshot Operations

  Create and retrieve snapshots:

      Eventual.save_snapshot("User", user_id, computed_state, 100)
      Eventual.get_latest_snapshot("User", user_id)
      Eventual.list_snapshots("User", user_id)

  ## State Reconstruction

  Efficiently rebuild aggregate state:

      {snapshot, events} = Eventual.get_aggregate_state("User", user_id)
  """

  alias Eventual.{Repo, Event, Snapshot, Query}

  @type aggregate_id :: String.t() | integer()
  @type aggregate_type :: String.t()
  @type event_type :: String.t()

  ## Event Operations

  @doc """
  Saves a single event to the event store.

  ## Parameters
  - `event_type` - Type of event (e.g., "user.created")
  - `aggregate_id` - ID of the entity this event relates to
  - `aggregate_type` - Type of entity (e.g., "User", "Order")
  - `data` - Event payload (will be stored as JSON)
  - `opts` - Optional parameters:
    - `:metadata` - Additional context map
    - `:occurred_at` - When the event occurred (defaults to now)
    - `:sequence_number` - Explicit sequence number (optional)

  ## Examples

      Eventual.save_event("user.created", "123", "User", %{name: "John"})

      Eventual.save_event("order.placed", order_id, "Order",
        %{items: [...]},
        metadata: %{user_id: "123", ip: "192.168.1.1"}
      )
  """
  @spec save_event(event_type(), aggregate_id(), aggregate_type(), map(), keyword()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def save_event(event_type, aggregate_id, aggregate_type, data, opts \\ []) do
    attrs = %{
      event_type: event_type,
      aggregate_id: to_string(aggregate_id),
      aggregate_type: aggregate_type,
      data: data,
      metadata: Keyword.get(opts, :metadata, %{}),
      occurred_at: Keyword.get(opts, :occurred_at),
      sequence_number: Keyword.get(opts, :sequence_number)
    }

    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Saves multiple events in a single database transaction.

  ## Parameters
  - `events` - List of event maps, each containing:
    - `:event_type`
    - `:aggregate_id`
    - `:aggregate_type`
    - `:data`
    - Optional: `:metadata`, `:occurred_at`, `:sequence_number`

  ## Examples

      events = [
        %{event_type: "user.created", aggregate_id: "1", aggregate_type: "User", data: %{}},
        %{event_type: "user.updated", aggregate_id: "1", aggregate_type: "User", data: %{}}
      ]
      Eventual.save_events(events)
  """
  @spec save_events([map()]) :: {:ok, [Event.t()]} | {:error, any()}
  def save_events(events) when is_list(events) do
    Repo.transaction(fn ->
      Enum.map(events, fn event_attrs ->
        %Event{}
        |> Event.changeset(event_attrs)
        |> Repo.insert!()
      end)
    end)
  end

  @doc """
  Retrieves a single event by ID.

  Returns `{:ok, event}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_event(binary()) :: {:ok, Event.t()} | {:error, :not_found}
  def get_event(id) do
    case Repo.get(Event, id) do
      nil -> {:error, :not_found}
      event -> {:ok, event}
    end
  end

  @doc """
  Lists events with optional filters.

  ## Filters
  - `:event_type` - Filter by event type
  - `:aggregate_type` - Filter by aggregate type
  - `:aggregate_id` - Filter by aggregate ID
  - `:from` - Events occurring after this datetime
  - `:to` - Events occurring before this datetime
  - `:limit` - Maximum number of results
  - `:order_by` - `:sequence_number`, `:occurred_at`, or `:inserted_at`

  ## Examples

      Eventual.list_events(event_type: "user.created", limit: 10)
      Eventual.list_events(aggregate_type: "Order", from: ~U[2024-01-01 00:00:00Z])
  """
  @spec list_events(keyword()) :: [Event.t()]
  def list_events(filters \\ []) do
    filters
    |> Query.events()
    |> Repo.all()
  end

  @doc """
  Streams events matching the given filters.

  More memory-efficient than `list_events/1` for large result sets.

  ## Examples

      Eventual.stream_events(aggregate_type: "User")
      |> Stream.map(&process_event/1)
      |> Stream.run()
  """
  @spec stream_events(keyword()) :: Enum.t()
  def stream_events(filters \\ []) do
    filters
    |> Query.events()
    |> Repo.stream()
  end

  @doc """
  Retrieves all events for a specific aggregate, ordered by sequence number.

  ## Options
  - `:from_sequence` - Only return events after this sequence number
  - `:limit` - Maximum number of results

  ## Examples

      Eventual.get_aggregate_events("User", "123")
      Eventual.get_aggregate_events("Order", order_id, from_sequence: 50)
  """
  @spec get_aggregate_events(aggregate_type(), aggregate_id(), keyword()) :: [Event.t()]
  def get_aggregate_events(aggregate_type, aggregate_id, opts \\ []) do
    aggregate_type
    |> Query.aggregate_events(to_string(aggregate_id), opts)
    |> Repo.all()
  end

  ## Snapshot Operations

  @doc """
  Saves a snapshot of an aggregate's state.

  ## Parameters
  - `aggregate_type` - Type of entity (e.g., "User")
  - `aggregate_id` - ID of the entity
  - `data` - Computed state to snapshot
  - `sequence_number` - Last event sequence number included in this state
  - `opts` - Optional parameters:
    - `:metadata` - Additional snapshot metadata

  ## Examples

      state = %{name: "John", email: "john@example.com", balance: 1000}
      Eventual.save_snapshot("User", "123", state, 100)
  """
  @spec save_snapshot(aggregate_type(), aggregate_id(), map(), integer(), keyword()) ::
          {:ok, Snapshot.t()} | {:error, Ecto.Changeset.t()}
  def save_snapshot(aggregate_type, aggregate_id, data, sequence_number, opts \\ []) do
    attrs = %{
      aggregate_type: aggregate_type,
      aggregate_id: to_string(aggregate_id),
      data: data,
      sequence_number: sequence_number,
      metadata: Keyword.get(opts, :metadata, %{})
    }

    %Snapshot{}
    |> Snapshot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retrieves the latest snapshot for an aggregate.

  Returns `{:ok, snapshot}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_latest_snapshot(aggregate_type(), aggregate_id()) ::
          {:ok, Snapshot.t()} | {:error, :not_found}
  def get_latest_snapshot(aggregate_type, aggregate_id) do
    case aggregate_type
         |> Query.latest_snapshot(to_string(aggregate_id))
         |> Repo.one() do
      nil -> {:error, :not_found}
      snapshot -> {:ok, snapshot}
    end
  end

  @doc """
  Retrieves a snapshot at a specific sequence number.

  Returns `{:ok, snapshot}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_snapshot_at(aggregate_type(), aggregate_id(), integer()) ::
          {:ok, Snapshot.t()} | {:error, :not_found}
  def get_snapshot_at(aggregate_type, aggregate_id, sequence_number) do
    case aggregate_type
         |> Query.snapshot_at(to_string(aggregate_id), sequence_number)
         |> Repo.one() do
      nil -> {:error, :not_found}
      snapshot -> {:ok, snapshot}
    end
  end

  @doc """
  Lists all snapshots for an aggregate, ordered by sequence number (descending).

  ## Options
  - `:limit` - Maximum number of results

  ## Examples

      Eventual.list_snapshots("User", "123", limit: 5)
  """
  @spec list_snapshots(aggregate_type(), aggregate_id(), keyword()) :: [Snapshot.t()]
  def list_snapshots(aggregate_type, aggregate_id, opts \\ []) do
    aggregate_type
    |> Query.aggregate_snapshots(to_string(aggregate_id), opts)
    |> Repo.all()
  end

  ## Combined Operations

  @doc """
  Retrieves the latest snapshot and all subsequent events for an aggregate.

  This is the most efficient way to rebuild aggregate state.

  Returns `{snapshot | nil, [events]}`.

  ## Examples

      {snapshot, events} = Eventual.get_aggregate_state("User", "123")

      state = if snapshot do
        Enum.reduce(events, snapshot.data, &apply_event/2)
      else
        Enum.reduce(events, %{}, &apply_event/2)
      end
  """
  @spec get_aggregate_state(aggregate_type(), aggregate_id()) ::
          {Snapshot.t() | nil, [Event.t()]}
  def get_aggregate_state(aggregate_type, aggregate_id) do
    aggregate_id_str = to_string(aggregate_id)

    snapshot =
      aggregate_type
      |> Query.latest_snapshot(aggregate_id_str)
      |> Repo.one()

    events =
      case snapshot do
        nil ->
          get_aggregate_events(aggregate_type, aggregate_id_str)

        %Snapshot{sequence_number: seq} ->
          aggregate_type
          |> Query.events_after_sequence(aggregate_id_str, seq)
          |> Repo.all()
      end

    {snapshot, events}
  end

  @doc """
  Rebuilds aggregate state from the latest snapshot and subsequent events.

  ## Parameters
  - `aggregate_type` - Type of entity
  - `aggregate_id` - ID of the entity
  - `apply_event_fn` - Function that applies an event to state: `(event, state) -> new_state`
  - `initial_state` - Initial state if no snapshot exists (default: `%{}`)

  ## Examples

      apply_user_event = fn event, state ->
        case event.event_type do
          "user.created" -> Map.merge(state, event.data)
          "user.updated" -> Map.merge(state, event.data)
          _ -> state
        end
      end

      state = Eventual.rebuild_from_snapshot("User", "123", apply_user_event, %{})
  """
  @spec rebuild_from_snapshot(
          aggregate_type(),
          aggregate_id(),
          (Event.t(), state :: any() -> any()),
          any()
        ) :: any()
  def rebuild_from_snapshot(aggregate_type, aggregate_id, apply_event_fn, initial_state \\ %{}) do
    {snapshot, events} = get_aggregate_state(aggregate_type, aggregate_id)

    starting_state = if snapshot, do: snapshot.data, else: initial_state

    Enum.reduce(events, starting_state, apply_event_fn)
  end
end
