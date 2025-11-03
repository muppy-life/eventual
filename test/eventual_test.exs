defmodule EventualTest do
  use ExUnit.Case, async: true

  alias Eventual.Repo
  alias Eventual.Event
  alias Eventual.Snapshot

  setup do
    # Explicitly get a connection before each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  describe "save_event/1" do
    test "saves a single event successfully" do
      event = %Event{
        event_type: "user.created",
        aggregate_id: "user-123",
        aggregate_type: "User",
        data: %{name: "John Doe", email: "john@example.com"}
      }

      {:ok, saved_event} = Eventual.save_event(event)

      assert saved_event.event_type == "user.created"
      assert saved_event.aggregate_id == "user-123"
      assert saved_event.aggregate_type == "User"
      assert saved_event.data == %{name: "John Doe", email: "john@example.com"}
      assert saved_event.metadata == %{}
      assert saved_event.id != nil
      assert saved_event.occurred_at != nil
      assert saved_event.inserted_at != nil
    end

    test "saves event with metadata" do
      event = %Event{
        event_type: "order.placed",
        aggregate_id: "order-456",
        aggregate_type: "Order",
        data: %{total: 99.99},
        metadata: %{user_id: "user-123", ip: "192.168.1.1"}
      }

      {:ok, saved_event} = Eventual.save_event(event)

      assert saved_event.metadata == %{user_id: "user-123", ip: "192.168.1.1"}
    end

    test "saves event with custom occurred_at timestamp" do
      custom_time = ~U[2024-01-15 10:30:00Z]

      event = %Event{
        event_type: "payment.completed",
        aggregate_id: "payment-789",
        aggregate_type: "Payment",
        data: %{amount: 50.00},
        occurred_at: custom_time
      }

      {:ok, saved_event} = Eventual.save_event(event)

      assert DateTime.compare(saved_event.occurred_at, custom_time) == :eq
    end

    test "saves event with sequence number" do
      event = %Event{
        event_type: "user.updated",
        aggregate_id: "user-123",
        aggregate_type: "User",
        data: %{email: "newemail@example.com"},
        sequence_number: 5
      }

      {:ok, saved_event} = Eventual.save_event(event)

      assert saved_event.sequence_number == 5
    end
  end

  describe "save_events/1" do
    test "saves multiple events in a transaction" do
      events = [
        %Event{
          event_type: "user.created",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{name: "Alice"}
        },
        %Event{
          event_type: "user.created",
          aggregate_id: "user-2",
          aggregate_type: "User",
          data: %{name: "Bob"}
        }
      ]

      {:ok, saved_events} = Eventual.save_events(events)

      assert length(saved_events) == 2
      assert Enum.at(saved_events, 0).data == %{name: "Alice"}
      assert Enum.at(saved_events, 1).data == %{name: "Bob"}
    end
  end

  describe "get_event/1" do
    test "retrieves an event by ID" do
      event = %Event{
        event_type: "user.created",
        aggregate_id: "user-123",
        aggregate_type: "User",
        data: %{name: "John"}
      }

      {:ok, created_event} = Eventual.save_event(event)

      {:ok, retrieved_event} = Eventual.get_event(created_event.id)

      assert retrieved_event.id == created_event.id
      assert retrieved_event.data == %{"name" => "John"}
    end

    test "returns error when event not found" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Eventual.get_event(fake_id)
    end
  end

  describe "list_events/1" do
    setup do
      # Create some test events
      Eventual.save_event(%Event{event_type: "user.created", aggregate_id: "user-1", aggregate_type: "User", data: %{name: "Alice"}})
      Eventual.save_event(%Event{event_type: "user.created", aggregate_id: "user-2", aggregate_type: "User", data: %{name: "Bob"}})
      Eventual.save_event(%Event{event_type: "order.placed", aggregate_id: "order-1", aggregate_type: "Order", data: %{total: 100}})
      :ok
    end

    test "lists all events without filters" do
      events = Eventual.list_events()
      assert length(events) >= 3
    end

    test "filters events by event_type" do
      events = Eventual.list_events(event_type: "user.created")
      assert length(events) == 2
      assert Enum.all?(events, &(&1.event_type == "user.created"))
    end

    test "filters events by aggregate_type" do
      events = Eventual.list_events(aggregate_type: "Order")
      assert length(events) == 1
      assert hd(events).aggregate_type == "Order"
    end

    test "limits number of results" do
      events = Eventual.list_events(limit: 2)
      assert length(events) == 2
    end
  end

  describe "get_aggregate_events/3" do
    test "retrieves all events for a specific aggregate" do
      # Create multiple events for the same aggregate
      Eventual.save_event(%Event{event_type: "user.created", aggregate_id: "user-123", aggregate_type: "User", data: %{name: "John"}, sequence_number: 1})
      Eventual.save_event(%Event{event_type: "user.updated", aggregate_id: "user-123", aggregate_type: "User", data: %{email: "john@example.com"}, sequence_number: 2})
      Eventual.save_event(%Event{event_type: "user.updated", aggregate_id: "user-123", aggregate_type: "User", data: %{name: "John Doe"}, sequence_number: 3})

      # Create event for different aggregate
      Eventual.save_event(%Event{event_type: "user.created", aggregate_id: "user-456", aggregate_type: "User", data: %{name: "Jane"}, sequence_number: 1})

      events = Eventual.get_aggregate_events("User", "user-123")

      assert length(events) == 3
      assert Enum.all?(events, &(&1.aggregate_id == "user-123"))
      # Should be ordered by sequence number
      assert Enum.at(events, 0).event_type == "user.created"
      assert Enum.at(events, 1).event_type == "user.updated"
    end

    test "retrieves events after a specific sequence number" do
      Eventual.save_event(%Event{event_type: "user.created", aggregate_id: "user-123", aggregate_type: "User", data: %{name: "John"}, sequence_number: 1})
      Eventual.save_event(%Event{event_type: "user.updated", aggregate_id: "user-123", aggregate_type: "User", data: %{email: "john@example.com"}, sequence_number: 2})
      Eventual.save_event(%Event{event_type: "user.updated", aggregate_id: "user-123", aggregate_type: "User", data: %{name: "John Doe"}, sequence_number: 3})

      events = Eventual.get_aggregate_events("User", "user-123", from_sequence: 1)

      assert length(events) == 2
      assert Enum.at(events, 0).sequence_number == 2
      assert Enum.at(events, 1).sequence_number == 3
    end
  end

  describe "save_snapshot/1" do
    test "saves a snapshot successfully" do
      state = %{name: "John Doe", email: "john@example.com", balance: 1000}

      snapshot = %Snapshot{
        aggregate_type: "User",
        aggregate_id: "user-123",
        data: state,
        sequence_number: 100
      }

      {:ok, saved_snapshot} = Eventual.save_snapshot(snapshot)

      assert saved_snapshot.aggregate_type == "User"
      assert saved_snapshot.aggregate_id == "user-123"
      assert saved_snapshot.data == state
      assert saved_snapshot.sequence_number == 100
      assert saved_snapshot.metadata == %{}
      assert saved_snapshot.id != nil
    end

    test "saves snapshot with metadata" do
      snapshot = %Snapshot{
        aggregate_type: "User",
        aggregate_id: "user-123",
        data: %{name: "John"},
        sequence_number: 50,
        metadata: %{created_by: "system"}
      }

      {:ok, saved_snapshot} = Eventual.save_snapshot(snapshot)

      assert saved_snapshot.metadata == %{created_by: "system"}
    end

    test "prevents duplicate snapshots at same sequence number" do
      snapshot1 = %Snapshot{
        aggregate_type: "User",
        aggregate_id: "user-123",
        data: %{name: "John"},
        sequence_number: 50
      }
      Eventual.save_snapshot(snapshot1)

      # Trying to save another snapshot at the same sequence should fail
      snapshot2 = %Snapshot{
        aggregate_type: "User",
        aggregate_id: "user-123",
        data: %{name: "Jane"},
        sequence_number: 50
      }
      assert {:error, changeset} = Eventual.save_snapshot(snapshot2)
      assert changeset.errors != []
    end
  end

  describe "get_latest_snapshot/2" do
    test "retrieves the latest snapshot for an aggregate" do
      # Create multiple snapshots
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 1}, sequence_number: 10})
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 2}, sequence_number: 20})
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 3}, sequence_number: 30})

      {:ok, snapshot} = Eventual.get_latest_snapshot("User", "user-123")

      assert snapshot.sequence_number == 30
      assert snapshot.data == %{"version" => 3}
    end

    test "returns error when no snapshot exists" do
      assert {:error, :not_found} = Eventual.get_latest_snapshot("User", "nonexistent")
    end
  end

  describe "get_snapshot_at/3" do
    test "retrieves a snapshot at specific sequence number" do
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 1}, sequence_number: 10})
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 2}, sequence_number: 20})

      {:ok, snapshot} = Eventual.get_snapshot_at("User", "user-123", 10)

      assert snapshot.sequence_number == 10
      assert snapshot.data == %{"version" => 1}
    end

    test "returns error when snapshot at sequence not found" do
      assert {:error, :not_found} = Eventual.get_snapshot_at("User", "user-123", 999)
    end
  end

  describe "list_snapshots/3" do
    test "lists all snapshots for an aggregate" do
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 1}, sequence_number: 10})
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 2}, sequence_number: 20})
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 3}, sequence_number: 30})

      snapshots = Eventual.list_snapshots("User", "user-123")

      assert length(snapshots) == 3
      # Should be in descending order
      assert Enum.at(snapshots, 0).sequence_number == 30
      assert Enum.at(snapshots, 1).sequence_number == 20
      assert Enum.at(snapshots, 2).sequence_number == 10
    end

    test "limits number of snapshots" do
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 1}, sequence_number: 10})
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 2}, sequence_number: 20})
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{version: 3}, sequence_number: 30})

      snapshots = Eventual.list_snapshots("User", "user-123", limit: 2)

      assert length(snapshots) == 2
    end
  end

  describe "get_aggregate_state/2" do
    test "returns snapshot and subsequent events" do
      # Create some events
      Eventual.save_event(%Event{event_type: "user.created", aggregate_id: "user-123", aggregate_type: "User", data: %{name: "John"}, sequence_number: 1})
      Eventual.save_event(%Event{event_type: "user.updated", aggregate_id: "user-123", aggregate_type: "User", data: %{email: "john@example.com"}, sequence_number: 2})

      # Create a snapshot after event 2
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{name: "John", email: "john@example.com"}, sequence_number: 2})

      # Create more events after snapshot
      Eventual.save_event(%Event{event_type: "user.updated", aggregate_id: "user-123", aggregate_type: "User", data: %{name: "John Doe"}, sequence_number: 3})
      Eventual.save_event(%Event{event_type: "user.updated", aggregate_id: "user-123", aggregate_type: "User", data: %{balance: 100}, sequence_number: 4})

      {snapshot, events} = Eventual.get_aggregate_state("User", "user-123")

      assert snapshot != nil
      assert snapshot.sequence_number == 2
      assert length(events) == 2  # Only events after snapshot
      assert Enum.at(events, 0).sequence_number == 3
      assert Enum.at(events, 1).sequence_number == 4
    end

    test "returns all events when no snapshot exists" do
      Eventual.save_event(%Event{event_type: "user.created", aggregate_id: "user-123", aggregate_type: "User", data: %{name: "John"}, sequence_number: 1})
      Eventual.save_event(%Event{event_type: "user.updated", aggregate_id: "user-123", aggregate_type: "User", data: %{email: "john@example.com"}, sequence_number: 2})

      {snapshot, events} = Eventual.get_aggregate_state("User", "user-123")

      assert snapshot == nil
      assert length(events) == 2
    end
  end

  describe "rebuild_from_snapshot/4" do
    test "rebuilds state from snapshot and subsequent events" do
      # Create events
      Eventual.save_event(%Event{event_type: "user.created", aggregate_id: "user-123", aggregate_type: "User", data: %{name: "John", balance: 0}, sequence_number: 1})
      Eventual.save_event(%Event{event_type: "user.balance_changed", aggregate_id: "user-123", aggregate_type: "User", data: %{amount: 100}, sequence_number: 2})

      # Create snapshot
      Eventual.save_snapshot(%Snapshot{aggregate_type: "User", aggregate_id: "user-123", data: %{name: "John", balance: 100}, sequence_number: 2})

      # More events after snapshot
      Eventual.save_event(%Event{event_type: "user.balance_changed", aggregate_id: "user-123", aggregate_type: "User", data: %{amount: 50}, sequence_number: 3})
      Eventual.save_event(%Event{event_type: "user.balance_changed", aggregate_id: "user-123", aggregate_type: "User", data: %{amount: -30}, sequence_number: 4})

      # Define event application function
      apply_event = fn event, state ->
        case event.event_type do
          "user.created" ->
            Map.merge(state, event.data)

          "user.balance_changed" ->
            Map.update(state, "balance", 0, &(&1 + event.data["amount"]))

          _ ->
            state
        end
      end

      state = Eventual.rebuild_from_snapshot("User", "user-123", apply_event, %{})

      # Should start from snapshot (balance: 100) and apply +50 and -30
      assert state["name"] == "John"
      assert state["balance"] == 120  # 100 + 50 - 30
    end

    test "rebuilds from scratch when no snapshot exists" do
      Eventual.save_event(%Event{event_type: "user.created", aggregate_id: "user-123", aggregate_type: "User", data: %{name: "Alice", balance: 0}, sequence_number: 1})
      Eventual.save_event(%Event{event_type: "user.balance_changed", aggregate_id: "user-123", aggregate_type: "User", data: %{amount: 75}, sequence_number: 2})

      apply_event = fn event, state ->
        case event.event_type do
          "user.created" -> Map.merge(state, event.data)
          "user.balance_changed" -> Map.update(state, "balance", 0, &(&1 + event.data["amount"]))
          _ -> state
        end
      end

      state = Eventual.rebuild_from_snapshot("User", "user-123", apply_event, %{"balance" => 0})

      assert state["name"] == "Alice"
      assert state["balance"] == 75
    end
  end
end
