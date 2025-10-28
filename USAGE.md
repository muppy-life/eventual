# Eventual - Usage Guide

This guide demonstrates how to use the Eventual event store library in your Elixir applications.

## Setup

### 1. Add to Dependencies

```elixir
# mix.exs
def deps do
  [
    {:eventual, "~> 0.1.0"}
  ]
end
```

### 2. Configure Database

```elixir
# config/config.exs
config :eventual, Eventual.Repo,
  database: "eventual_events",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool_size: 10
```

### 3. Create Database and Run Migrations

```bash
# Create the database
mix ecto.create -r Eventual.Repo

# Run migrations
mix ecto.migrate -r Eventual.Repo
```

## Basic Usage

### Saving Events

```elixir
# Save a single event
{:ok, event} = Eventual.save_event(
  "user.created",           # event type
  "user-123",               # aggregate ID
  "User",                   # aggregate type
  %{                        # event data
    name: "John Doe",
    email: "john@example.com"
  }
)

# Save event with metadata
{:ok, event} = Eventual.save_event(
  "order.placed",
  order_id,
  "Order",
  %{items: ["item1", "item2"], total: 99.99},
  metadata: %{user_id: "user-123", ip: "192.168.1.1"}
)

# Save event with custom timestamp
{:ok, event} = Eventual.save_event(
  "payment.completed",
  payment_id,
  "Payment",
  %{amount: 50.00, method: "credit_card"},
  occurred_at: ~U[2024-01-15 10:30:00Z]
)
```

### Batch Saving Events

```elixir
# Save multiple events in a transaction
events = [
  %{
    event_type: "user.created",
    aggregate_id: "user-1",
    aggregate_type: "User",
    data: %{name: "Alice"}
  },
  %{
    event_type: "user.created",
    aggregate_id: "user-2",
    aggregate_type: "User",
    data: %{name: "Bob"}
  }
]

{:ok, saved_events} = Eventual.save_events(events)
```

### Retrieving Events

```elixir
# Get a specific event by ID
{:ok, event} = Eventual.get_event(event_id)

# Get all events for a specific aggregate
events = Eventual.get_aggregate_events("User", "user-123")

# Get events with filters
events = Eventual.list_events(
  event_type: "user.created",
  limit: 10
)

# Get events by aggregate type
events = Eventual.list_events(
  aggregate_type: "Order",
  from: ~U[2024-01-01 00:00:00Z],
  to: ~U[2024-12-31 23:59:59Z]
)

# Stream large result sets
Eventual.stream_events(aggregate_type: "User")
|> Stream.map(&process_event/1)
|> Stream.run()
```

## Working with Snapshots

### Creating Snapshots

```elixir
# After processing many events, save a snapshot of the current state
user_state = %{
  id: "user-123",
  name: "John Doe",
  email: "john@example.com",
  balance: 1000.00,
  orders_count: 50
}

{:ok, snapshot} = Eventual.save_snapshot(
  "User",                   # aggregate type
  "user-123",               # aggregate ID
  user_state,               # computed state
  100                       # sequence number (last event processed)
)

# Snapshot with metadata
{:ok, snapshot} = Eventual.save_snapshot(
  "User",
  "user-123",
  user_state,
  100,
  metadata: %{created_by: "background_job", reason: "daily_snapshot"}
)
```

### Retrieving Snapshots

```elixir
# Get the latest snapshot
{:ok, snapshot} = Eventual.get_latest_snapshot("User", "user-123")

# Get snapshot at specific sequence number
{:ok, snapshot} = Eventual.get_snapshot_at("User", "user-123", 50)

# List all snapshots for an aggregate
snapshots = Eventual.list_snapshots("User", "user-123", limit: 5)
```

## State Reconstruction

### Manual Reconstruction

```elixir
# Get snapshot and subsequent events
{snapshot, events} = Eventual.get_aggregate_state("User", "user-123")

# Manually apply events
state = if snapshot do
  # Start from snapshot state
  Enum.reduce(events, snapshot.data, fn event, state ->
    apply_event_to_user(event, state)
  end)
else
  # No snapshot, start from scratch
  Enum.reduce(events, %{}, fn event, state ->
    apply_event_to_user(event, state)
  end)
end

defp apply_event_to_user(event, state) do
  case event.event_type do
    "user.created" ->
      Map.merge(state, event.data)

    "user.updated" ->
      Map.merge(state, event.data)

    "user.balance_changed" ->
      Map.update!(state, :balance, &(&1 + event.data.amount))

    _ ->
      state
  end
end
```

### Automatic Reconstruction

```elixir
# Use the built-in rebuild function
apply_user_event = fn event, state ->
  case event.event_type do
    "user.created" -> Map.merge(state, event.data)
    "user.updated" -> Map.merge(state, event.data)
    "user.balance_changed" -> Map.update!(state, :balance, &(&1 + event.data.amount))
    _ -> state
  end
end

current_state = Eventual.rebuild_from_snapshot(
  "User",
  "user-123",
  apply_user_event,
  %{}  # initial state if no snapshot exists
)
```

## Complete Example: E-commerce Order Flow

```elixir
defmodule MyApp.OrderService do
  @moduledoc """
  Service for managing orders using event sourcing.
  """

  # Create a new order
  def create_order(order_id, customer_id, items) do
    Eventual.save_event(
      "order.created",
      order_id,
      "Order",
      %{
        customer_id: customer_id,
        items: items,
        status: "pending",
        total: calculate_total(items)
      },
      metadata: %{customer_id: customer_id}
    )
  end

  # Add item to order
  def add_item(order_id, item) do
    Eventual.save_event(
      "order.item_added",
      order_id,
      "Order",
      %{item: item}
    )
  end

  # Complete the order
  def complete_order(order_id, payment_info) do
    events = [
      %{
        event_type: "order.payment_received",
        aggregate_id: order_id,
        aggregate_type: "Order",
        data: %{payment: payment_info}
      },
      %{
        event_type: "order.completed",
        aggregate_id: order_id,
        aggregate_type: "Order",
        data: %{completed_at: DateTime.utc_now()}
      }
    ]

    Eventual.save_events(events)
  end

  # Get order history
  def get_order_history(order_id) do
    Eventual.get_aggregate_events("Order", order_id)
  end

  # Rebuild current order state
  def get_current_order_state(order_id) do
    Eventual.rebuild_from_snapshot(
      "Order",
      order_id,
      &apply_order_event/2,
      %{items: [], status: "new", total: 0}
    )
  end

  # Create snapshot after significant changes
  def snapshot_order(order_id, sequence_number) do
    state = get_current_order_state(order_id)
    Eventual.save_snapshot("Order", order_id, state, sequence_number)
  end

  # Apply order events to rebuild state
  defp apply_order_event(event, state) do
    case event.event_type do
      "order.created" ->
        Map.merge(state, event.data)

      "order.item_added" ->
        items = [event.data.item | state.items]
        total = calculate_total(items)
        %{state | items: items, total: total}

      "order.payment_received" ->
        Map.put(state, :payment, event.data.payment)

      "order.completed" ->
        Map.merge(state, %{status: "completed", completed_at: event.data.completed_at})

      _ ->
        state
    end
  end

  defp calculate_total(items) do
    Enum.reduce(items, 0, fn item, acc -> acc + item.price end)
  end
end
```

## Advanced Querying

### Filter by Time Range

```elixir
# Get events from last week
one_week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

events = Eventual.list_events(
  event_type: "user.login",
  from: one_week_ago,
  order_by: :occurred_at
)
```

### Pagination

```elixir
# Get first page
page_1 = Eventual.list_events(
  aggregate_type: "Order",
  limit: 10,
  order_by: :inserted_at
)

# Use last event's timestamp for next page
last_event = List.last(page_1)

page_2 = Eventual.list_events(
  aggregate_type: "Order",
  from: last_event.inserted_at,
  limit: 10,
  order_by: :inserted_at
)
```

### Get Events After Snapshot

```elixir
# Efficient: only get events we haven't processed
{:ok, snapshot} = Eventual.get_latest_snapshot("User", user_id)

new_events = Eventual.get_aggregate_events(
  "User",
  user_id,
  from_sequence: snapshot.sequence_number
)
```

## Best Practices

### 1. Event Naming
Use clear, past-tense event names:
- ✅ `user.created`, `order.placed`, `payment.completed`
- ❌ `create_user`, `place_order`, `complete_payment`

### 2. Snapshot Strategy
Create snapshots:
- After every N events (e.g., every 100 events)
- On a schedule (e.g., daily for active aggregates)
- Before expensive state reconstructions

### 3. Metadata Usage
Store correlation IDs and causation IDs in metadata:
```elixir
Eventual.save_event(
  "order.created",
  order_id,
  "Order",
  order_data,
  metadata: %{
    correlation_id: correlation_id,  # Links related events
    causation_id: originating_event_id,  # What caused this event
    user_id: user_id
  }
)
```

### 4. Sequence Numbers
Let the application manage sequence numbers when order matters:
```elixir
# Get next sequence number
last_event = Eventual.get_aggregate_events("User", user_id, limit: 1)
next_seq = if last_event, do: last_event.sequence_number + 1, else: 1

Eventual.save_event(
  "user.updated",
  user_id,
  "User",
  data,
  sequence_number: next_seq
)
```

### 5. Transaction Boundaries
Use `save_events/1` when multiple events must be atomic:
```elixir
# These events must all succeed or all fail together
events = [
  %{event_type: "inventory.reserved", ...},
  %{event_type: "order.created", ...},
  %{event_type: "payment.pending", ...}
]

{:ok, _} = Eventual.save_events(events)
```

## Troubleshooting

### Database Connection Issues
```elixir
# Test the connection
Eventual.Repo.query("SELECT 1")

# Check if repo is running
Process.whereis(Eventual.Repo)
```

### Event Replay Performance
If event replay is slow:
1. Create more frequent snapshots
2. Add database indexes for your query patterns
3. Use `stream_events/1` instead of `list_events/1`

### Viewing Events in Database
```sql
-- See all events for a user
SELECT * FROM events
WHERE aggregate_type = 'User'
  AND aggregate_id = 'user-123'
ORDER BY sequence_number;

-- Latest snapshots
SELECT DISTINCT ON (aggregate_type, aggregate_id) *
FROM snapshots
ORDER BY aggregate_type, aggregate_id, sequence_number DESC;
```
