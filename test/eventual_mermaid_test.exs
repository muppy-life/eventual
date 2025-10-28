defmodule EventualMermaidTest do
  use ExUnit.Case, async: true
  alias Eventual.{Event, Mermaid}

  describe "timeline/2" do
    test "generates basic timeline from events" do
      events = [
        %Event{
          event_type: "user.created",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{name: "Alice"},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        },
        %Event{
          event_type: "user.updated",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{name: "Alice Smith"},
          metadata: %{},
          sequence_number: 2,
          occurred_at: ~U[2024-01-02 11:00:00Z]
        }
      ]

      result = Mermaid.timeline(events)

      assert result =~ "timeline"
      assert result =~ "title Event Timeline"
      assert result =~ "2024-01-01 : user.created (user-1)"
      assert result =~ "2024-01-02 : user.updated (user-1)"
    end

    test "generates timeline with custom title" do
      events = [
        %Event{
          event_type: "order.created",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        }
      ]

      result = Mermaid.timeline(events, title: "Order Events")

      assert result =~ "title Order Events"
    end

    test "handles events with different date formats" do
      events = [
        %Event{
          event_type: "user.created",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-15 14:30:45Z]
        }
      ]

      result_short = Mermaid.timeline(events, date_format: :short)
      assert result_short =~ "2024-01-15"

      result_long = Mermaid.timeline(events, date_format: :long)
      assert result_long =~ "2024-01-15 14:30"

      result_timestamp = Mermaid.timeline(events, date_format: :timestamp)
      assert result_timestamp =~ to_string(DateTime.to_unix(~U[2024-01-15 14:30:45Z]))
    end

    test "handles empty event list" do
      result = Mermaid.timeline([])

      assert result =~ "timeline"
      assert result =~ "title Event Timeline"
    end
  end

  describe "flowchart/2" do
    test "generates basic flowchart from events" do
      events = [
        %Event{
          event_type: "user.created",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        },
        %Event{
          event_type: "user.updated",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{},
          metadata: %{},
          sequence_number: 2,
          occurred_at: ~U[2024-01-02 11:00:00Z]
        }
      ]

      result = Mermaid.flowchart(events)

      assert result =~ "flowchart TD"
      assert result =~ "Start([Start])"
      assert result =~ "End([End])"
      assert result =~ "E0[user.created]"
      assert result =~ "E1[user.updated]"
      assert result =~ "Start --> E0"
      assert result =~ "E0 --> E1"
      assert result =~ "E1 --> End"
    end

    test "generates flowchart with custom direction" do
      events = [
        %Event{
          event_type: "order.created",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        }
      ]

      result = Mermaid.flowchart(events, direction: :LR)

      assert result =~ "flowchart LR"
    end

    test "generates flowchart with event data" do
      events = [
        %Event{
          event_type: "user.created",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{name: "Alice", email: "alice@example.com", age: 30},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        }
      ]

      result = Mermaid.flowchart(events, show_data: true)

      assert result =~ "user.created"
      assert result =~ "<br/>"
    end

    test "handles empty event list" do
      result = Mermaid.flowchart([])

      assert result =~ "flowchart TD"
      assert result =~ "Start --> End"
    end
  end

  describe "sequence_diagram/2" do
    test "generates basic sequence diagram" do
      events = [
        %Event{
          event_type: "order.created",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        },
        %Event{
          event_type: "order.paid",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{},
          metadata: %{},
          sequence_number: 2,
          occurred_at: ~U[2024-01-01 11:00:00Z]
        }
      ]

      result = Mermaid.sequence_diagram(events)

      assert result =~ "sequenceDiagram"
      assert result =~ "participant Order"
      assert result =~ "Order->>Order: order.created"
      assert result =~ "Order->>Order: order.paid"
    end

    test "generates sequence diagram with metadata" do
      events = [
        %Event{
          event_type: "user.created",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{},
          metadata: %{ip: "192.168.1.1", user_agent: "Mozilla"},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        }
      ]

      result = Mermaid.sequence_diagram(events, show_metadata: true)

      assert result =~ "Note over User:"
      assert result =~ "ip:"
      assert result =~ "user_agent:"
    end

    test "handles multiple aggregate types" do
      events = [
        %Event{
          event_type: "order.created",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        },
        %Event{
          event_type: "user.notified",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:01:00Z]
        }
      ]

      result = Mermaid.sequence_diagram(events)

      assert result =~ "participant Order"
      assert result =~ "participant User"
    end
  end

  describe "state_diagram/2" do
    test "generates basic state diagram" do
      events = [
        %Event{
          event_type: "order.created",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{status: "pending"},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        },
        %Event{
          event_type: "order.paid",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{status: "paid"},
          metadata: %{},
          sequence_number: 2,
          occurred_at: ~U[2024-01-01 11:00:00Z]
        },
        %Event{
          event_type: "order.shipped",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{status: "shipped"},
          metadata: %{},
          sequence_number: 3,
          occurred_at: ~U[2024-01-01 12:00:00Z]
        }
      ]

      result = Mermaid.state_diagram(events)

      assert result =~ "stateDiagram-v2"
      assert result =~ "[*] --> pending : order.created"
      assert result =~ "pending --> paid : order.paid"
      assert result =~ "paid --> shipped : order.shipped"
      assert result =~ "shipped --> [*]"
    end

    test "generates state diagram with custom state extractor" do
      events = [
        %Event{
          event_type: "user.created",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{state: "active"},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        },
        %Event{
          event_type: "user.suspended",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{state: "suspended"},
          metadata: %{},
          sequence_number: 2,
          occurred_at: ~U[2024-01-01 11:00:00Z]
        }
      ]

      state_extractor = fn event -> event.data["state"] || event.data[:state] end
      result = Mermaid.state_diagram(events, state_extractor: state_extractor)

      assert result =~ "active"
      assert result =~ "suspended"
    end

    test "handles events without explicit status" do
      events = [
        %Event{
          event_type: "user.created",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        },
        %Event{
          event_type: "user.updated",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{},
          metadata: %{},
          sequence_number: 2,
          occurred_at: ~U[2024-01-01 11:00:00Z]
        }
      ]

      result = Mermaid.state_diagram(events)

      assert result =~ "stateDiagram-v2"
      assert result =~ "Created"
      assert result =~ "Updated"
    end
  end

  describe "graph/2" do
    test "generates basic graph diagram" do
      events = [
        %Event{
          event_type: "order.created",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        },
        %Event{
          event_type: "user.created",
          aggregate_id: "user-1",
          aggregate_type: "User",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        }
      ]

      result = Mermaid.graph(events)

      assert result =~ "graph LR"
      assert result =~ "Order"
      assert result =~ "User"
      assert result =~ "order-1"
      assert result =~ "user-1"
    end

    test "generates graph with custom direction" do
      events = [
        %Event{
          event_type: "order.created",
          aggregate_id: "order-1",
          aggregate_type: "Order",
          data: %{},
          metadata: %{},
          sequence_number: 1,
          occurred_at: ~U[2024-01-01 10:00:00Z]
        }
      ]

      result = Mermaid.graph(events, direction: :TD)

      assert result =~ "graph TD"
    end
  end
end
