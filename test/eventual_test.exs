defmodule EventualTest do
  use ExUnit.Case, async: true

  alias Eventual.Repo

  setup do
    # Explicitly get a connection before each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  describe "save_event/5" do
    test "saves a single event successfully" do
      {:ok, event} = Eventual.save_event(
        "user.created",
        "user-123",
        "User",
        %{name: "John Doe", email: "john@example.com"}
      )

      assert event.event_type == "user.created"
      assert event.aggregate_id == "user-123"
      assert event.aggregate_type == "User"
      assert event.data == %{name: "John Doe", email: "john@example.com"}
      assert event.metadata == %{}
      assert event.id != nil
      assert event.occurred_at != nil
      assert event.inserted_at != nil
    end

    test "saves event with metadata" do
      {:ok, event} = Eventual.save_event(
        "order.placed",
        "order-456",
        "Order",
        %{total: 99.99},
        metadata: %{user_id: "user-123", ip: "192.168.1.1"}
      )

      assert event.metadata == %{user_id: "user-123", ip: "192.168.1.1"}
    end

    test "saves event with custom occurred_at timestamp" do
      custom_time = ~U[2024-01-15 10:30:00Z]

      {:ok, event} = Eventual.save_event(
        "payment.completed",
        "payment-789",
        "Payment",
        %{amount: 50.00},
        occurred_at: custom_time
      )

      assert DateTime.compare(event.occurred_at, custom_time) == :eq
    end

    test "saves event with sequence number" do
      {:ok, event} = Eventual.save_event(
        "user.updated",
        "user-123",
        "User",
        %{email: "newemail@example.com"},
        sequence_number: 5
      )

      assert event.sequence_number == 5
    end
  end

  describe "save_events/1" do
    test "saves multiple events in a transaction" do
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

      assert length(saved_events) == 2
      assert Enum.at(saved_events, 0).data == %{name: "Alice"}
      assert Enum.at(saved_events, 1).data == %{name: "Bob"}
    end
  end

  describe "get_event/1" do
    test "retrieves an event by ID" do
      {:ok, created_event} = Eventual.save_event(
        "user.created",
        "user-123",
        "User",
        %{name: "John"}
      )

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
      Eventual.save_event("user.created", "user-1", "User", %{name: "Alice"})
      Eventual.save_event("user.created", "user-2", "User", %{name: "Bob"})
      Eventual.save_event("order.placed", "order-1", "Order", %{total: 100})
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
      Eventual.save_event("user.created", "user-123", "User", %{name: "John"}, sequence_number: 1)
      Eventual.save_event("user.updated", "user-123", "User", %{email: "john@example.com"}, sequence_number: 2)
      Eventual.save_event("user.updated", "user-123", "User", %{name: "John Doe"}, sequence_number: 3)

      # Create event for different aggregate
      Eventual.save_event("user.created", "user-456", "User", %{name: "Jane"}, sequence_number: 1)

      events = Eventual.get_aggregate_events("User", "user-123")

      assert length(events) == 3
      assert Enum.all?(events, &(&1.aggregate_id == "user-123"))
      # Should be ordered by sequence number
      assert Enum.at(events, 0).event_type == "user.created"
      assert Enum.at(events, 1).event_type == "user.updated"
    end

    test "retrieves events after a specific sequence number" do
      Eventual.save_event("user.created", "user-123", "User", %{name: "John"}, sequence_number: 1)
      Eventual.save_event("user.updated", "user-123", "User", %{email: "john@example.com"}, sequence_number: 2)
      Eventual.save_event("user.updated", "user-123", "User", %{name: "John Doe"}, sequence_number: 3)

      events = Eventual.get_aggregate_events("User", "user-123", from_sequence: 1)

      assert length(events) == 2
      assert Enum.at(events, 0).sequence_number == 2
      assert Enum.at(events, 1).sequence_number == 3
    end
  end

  describe "save_snapshot/5" do
    test "saves a snapshot successfully" do
      state = %{name: "John Doe", email: "john@example.com", balance: 1000}

      {:ok, snapshot} = Eventual.save_snapshot("User", "user-123", state, 100)

      assert snapshot.aggregate_type == "User"
      assert snapshot.aggregate_id == "user-123"
      assert snapshot.data == state
      assert snapshot.sequence_number == 100
      assert snapshot.metadata == %{}
      assert snapshot.id != nil
    end

    test "saves snapshot with metadata" do
      {:ok, snapshot} = Eventual.save_snapshot(
        "User",
        "user-123",
        %{name: "John"},
        50,
        metadata: %{created_by: "system"}
      )

      assert snapshot.metadata == %{created_by: "system"}
    end

    test "prevents duplicate snapshots at same sequence number" do
      Eventual.save_snapshot("User", "user-123", %{name: "John"}, 50)

      # Trying to save another snapshot at the same sequence should fail
      assert {:error, changeset} = Eventual.save_snapshot("User", "user-123", %{name: "Jane"}, 50)
      assert changeset.errors != []
    end
  end

  describe "get_latest_snapshot/2" do
    test "retrieves the latest snapshot for an aggregate" do
      # Create multiple snapshots
      Eventual.save_snapshot("User", "user-123", %{version: 1}, 10)
      Eventual.save_snapshot("User", "user-123", %{version: 2}, 20)
      Eventual.save_snapshot("User", "user-123", %{version: 3}, 30)

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
      Eventual.save_snapshot("User", "user-123", %{version: 1}, 10)
      Eventual.save_snapshot("User", "user-123", %{version: 2}, 20)

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
      Eventual.save_snapshot("User", "user-123", %{version: 1}, 10)
      Eventual.save_snapshot("User", "user-123", %{version: 2}, 20)
      Eventual.save_snapshot("User", "user-123", %{version: 3}, 30)

      snapshots = Eventual.list_snapshots("User", "user-123")

      assert length(snapshots) == 3
      # Should be in descending order
      assert Enum.at(snapshots, 0).sequence_number == 30
      assert Enum.at(snapshots, 1).sequence_number == 20
      assert Enum.at(snapshots, 2).sequence_number == 10
    end

    test "limits number of snapshots" do
      Eventual.save_snapshot("User", "user-123", %{version: 1}, 10)
      Eventual.save_snapshot("User", "user-123", %{version: 2}, 20)
      Eventual.save_snapshot("User", "user-123", %{version: 3}, 30)

      snapshots = Eventual.list_snapshots("User", "user-123", limit: 2)

      assert length(snapshots) == 2
    end
  end

  describe "get_aggregate_state/2" do
    test "returns snapshot and subsequent events" do
      # Create some events
      Eventual.save_event("user.created", "user-123", "User", %{name: "John"}, sequence_number: 1)
      Eventual.save_event("user.updated", "user-123", "User", %{email: "john@example.com"}, sequence_number: 2)

      # Create a snapshot after event 2
      Eventual.save_snapshot("User", "user-123", %{name: "John", email: "john@example.com"}, 2)

      # Create more events after snapshot
      Eventual.save_event("user.updated", "user-123", "User", %{name: "John Doe"}, sequence_number: 3)
      Eventual.save_event("user.updated", "user-123", "User", %{balance: 100}, sequence_number: 4)

      {snapshot, events} = Eventual.get_aggregate_state("User", "user-123")

      assert snapshot != nil
      assert snapshot.sequence_number == 2
      assert length(events) == 2  # Only events after snapshot
      assert Enum.at(events, 0).sequence_number == 3
      assert Enum.at(events, 1).sequence_number == 4
    end

    test "returns all events when no snapshot exists" do
      Eventual.save_event("user.created", "user-123", "User", %{name: "John"}, sequence_number: 1)
      Eventual.save_event("user.updated", "user-123", "User", %{email: "john@example.com"}, sequence_number: 2)

      {snapshot, events} = Eventual.get_aggregate_state("User", "user-123")

      assert snapshot == nil
      assert length(events) == 2
    end
  end

  describe "rebuild_from_snapshot/4" do
    test "rebuilds state from snapshot and subsequent events" do
      # Create events
      Eventual.save_event("user.created", "user-123", "User", %{name: "John", balance: 0}, sequence_number: 1)
      Eventual.save_event("user.balance_changed", "user-123", "User", %{amount: 100}, sequence_number: 2)

      # Create snapshot
      Eventual.save_snapshot("User", "user-123", %{name: "John", balance: 100}, 2)

      # More events after snapshot
      Eventual.save_event("user.balance_changed", "user-123", "User", %{amount: 50}, sequence_number: 3)
      Eventual.save_event("user.balance_changed", "user-123", "User", %{amount: -30}, sequence_number: 4)

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
      Eventual.save_event("user.created", "user-123", "User", %{name: "Alice", balance: 0}, sequence_number: 1)
      Eventual.save_event("user.balance_changed", "user-123", "User", %{amount: 75}, sequence_number: 2)

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
