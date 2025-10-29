defmodule Eventual.Mermaid do
  @moduledoc """
  Generates Mermaid diagram syntax from event sequences.

  Provides functions to visualize event sourcing data using Mermaid diagrams,
  including sequence diagrams, flowcharts, timelines, and state diagrams.

  ## Examples

      # Generate a timeline from events
      events = [
        %Eventual.Event{event_type: "user.created", aggregate_id: "user-1", ...},
        %Eventual.Event{event_type: "user.updated", aggregate_id: "user-1", ...}
      ]

      Eventual.Mermaid.timeline(events)
      # Returns Mermaid timeline syntax

      # Generate a flowchart
      Eventual.Mermaid.flowchart(events)
      # Returns Mermaid flowchart syntax

      # Generate a state diagram
      Eventual.Mermaid.state_diagram(events)
      # Returns Mermaid state diagram syntax
  """

  @doc """
  Generates a Mermaid timeline diagram from a list of events.

  Timeline diagrams show events in chronological order with their timestamps.

  ## Parameters

    - `events` - List of `Eventual.Event` structs
    - `opts` - Optional keyword list:
      - `:title` - Custom title for the timeline (default: "Event Timeline")
      - `:date_format` - How to format dates (`:short`, `:long`, or `:timestamp`, default: `:short`)

  ## Returns

  A string containing Mermaid timeline syntax.

  ## Examples

      iex> events = [
      ...>   %Eventual.Event{
      ...>     event_type: "user.created",
      ...>     aggregate_id: "user-1",
      ...>     occurred_at: ~U[2024-01-01 10:00:00Z]
      ...>   }
      ...> ]
      iex> Eventual.Mermaid.timeline(events)
      "timeline\\n    title Event Timeline\\n    2024-01-01 : user.created (user-1)\\n"
  """
  def timeline(events, opts \\ []) do
    title = Keyword.get(opts, :title, "Event Timeline")
    date_format = Keyword.get(opts, :date_format, :short)

    lines =
      events
      |> Enum.sort_by(& &1.occurred_at, DateTime)
      |> Enum.map(fn event ->
        date_str = format_date(event.occurred_at, date_format)
        "    #{date_str} : #{event.event_type} (#{event.aggregate_id})"
      end)

    ["timeline", "    title #{title}" | lines]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Generates a Mermaid flowchart diagram from a list of events.

  Flowcharts show the sequence of events with their relationships and data flow.
  Events are ordered by sequence_number (if available) or by occurred_at timestamp.

  ## Parameters

    - `events` - List of `Eventual.Event` structs
    - `opts` - Optional keyword list:
      - `:direction` - Flow direction (`:TD` top-down, `:LR` left-right, default: `:TD`)
      - `:show_data` - Include event data in nodes (default: `false`)

  ## Returns

  A string containing Mermaid flowchart syntax with ordering information.

  ## Examples

      iex> events = [
      ...>   %Eventual.Event{event_type: "user.created", aggregate_id: "user-1"},
      ...>   %Eventual.Event{event_type: "user.updated", aggregate_id: "user-1"}
      ...> ]
      iex> Eventual.Mermaid.flowchart(events, direction: :LR)
  """
  def flowchart(events, opts \\ []) do
    direction = Keyword.get(opts, :direction, :TD)
    show_data = Keyword.get(opts, :show_data, false)

    has_sequence_numbers = Enum.all?(events, fn e -> not is_nil(e.sequence_number) end)

    {sorted_events, order_by} =
      if has_sequence_numbers do
        {Enum.sort_by(events, & &1.sequence_number), "sequence_number"}
      else
        {Enum.sort_by(events, & &1.occurred_at, DateTime), "occurred_at"}
      end

    nodes =
      sorted_events
      |> Enum.with_index()
      |> Enum.map(fn {event, idx} ->
        node_id = "E#{idx}"
        order_value = if has_sequence_numbers, do: event.sequence_number, else: format_timestamp(event.occurred_at)
        label = format_event_label(event, show_data, order_value, order_by)
        "    #{node_id}[#{label}]"
      end)

    edges =
      sorted_events
      |> Enum.with_index()
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{_, idx1}, {_, idx2}] ->
        "    E#{idx1} --> E#{idx2}"
      end)

    start_node = "    Start([Start])"
    end_node = "    End([End])"

    start_edge =
      if length(sorted_events) > 0 do
        ["    Start --> E0"]
      else
        []
      end

    end_edge =
      if length(sorted_events) > 0 do
        last_idx = length(sorted_events) - 1
        ["    E#{last_idx} --> End"]
      else
        ["    Start --> End"]
      end

    ordering_comment = "    %% Events ordered by: #{order_by}"

    ["flowchart #{direction}", ordering_comment, start_node | nodes]
    |> Kernel.++(start_edge)
    |> Kernel.++(edges)
    |> Kernel.++(end_edge)
    |> Kernel.++([end_node])
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Generates a Mermaid sequence diagram from a list of events.

  Sequence diagrams show interactions between aggregates over time.

  ## Parameters

    - `events` - List of `Eventual.Event` structs
    - `opts` - Optional keyword list:
      - `:title` - Custom title for the diagram
      - `:show_metadata` - Include metadata in notes (default: `false`)

  ## Returns

  A string containing Mermaid sequence diagram syntax.

  ## Examples

      iex> events = [
      ...>   %Eventual.Event{
      ...>     event_type: "order.created",
      ...>     aggregate_type: "Order",
      ...>     aggregate_id: "order-1"
      ...>   }
      ...> ]
      iex> Eventual.Mermaid.sequence_diagram(events)
  """
  def sequence_diagram(events, opts \\ []) do
    show_metadata = Keyword.get(opts, :show_metadata, false)

    sorted_events =
      events
      |> Enum.sort_by(& &1.occurred_at, DateTime)

    # Extract unique aggregate types
    participants =
      sorted_events
      |> Enum.map(& &1.aggregate_type)
      |> Enum.uniq()
      |> Enum.map(&"    participant #{&1}")

    interactions =
      sorted_events
      |> Enum.map(fn event ->
        from = event.aggregate_type
        to = event.aggregate_type
        message = "#{event.event_type}"

        note =
          if show_metadata and event.metadata != %{} do
            metadata_str =
              event.metadata
              |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
              |> Enum.join(", ")

            ["    Note over #{from}: #{metadata_str}"]
          else
            []
          end

        ["    #{from}->>#{to}: #{message}"] ++ note
      end)
      |> List.flatten()

    ["sequenceDiagram"]
    |> Kernel.++(participants)
    |> Kernel.++(interactions)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Generates a Mermaid state diagram from a list of events.

  State diagrams show how an aggregate transitions through different states
  based on event types.

  ## Parameters

    - `events` - List of `Eventual.Event` structs
    - `opts` - Optional keyword list:
      - `:state_extractor` - Function to extract state from event (default: uses event_type)

  ## Returns

  A string containing Mermaid state diagram syntax.

  ## Examples

      iex> events = [
      ...>   %Eventual.Event{event_type: "order.created", data: %{status: "pending"}},
      ...>   %Eventual.Event{event_type: "order.paid", data: %{status: "paid"}},
      ...>   %Eventual.Event{event_type: "order.shipped", data: %{status: "shipped"}}
      ...> ]
      iex> Eventual.Mermaid.state_diagram(events)
  """
  def state_diagram(events, opts \\ []) do
    state_extractor = Keyword.get(opts, :state_extractor, &default_state_extractor/1)

    sorted_events =
      events
      |> Enum.sort_by(& &1.sequence_number)

    # Extract states and transitions
    states_and_transitions =
      sorted_events
      |> Enum.reduce({[], nil}, fn event, {acc, prev_state} ->
        current_state = state_extractor.(event)

        transition =
          if prev_state do
            "    #{prev_state} --> #{current_state} : #{event.event_type}"
          else
            "    [*] --> #{current_state} : #{event.event_type}"
          end

        {[transition | acc], current_state}
      end)
      |> elem(0)
      |> Enum.reverse()

    # Add final state transition
    final_transition =
      if length(sorted_events) > 0 do
        last_event = List.last(sorted_events)
        last_state = state_extractor.(last_event)
        ["    #{last_state} --> [*]"]
      else
        []
      end

    ["stateDiagram-v2"]
    |> Kernel.++(states_and_transitions)
    |> Kernel.++(final_transition)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Generates a Mermaid graph diagram showing relationships between aggregates.

  ## Parameters

    - `events` - List of `Eventual.Event` structs
    - `opts` - Optional keyword list:
      - `:direction` - Graph direction (`:TD`, `:LR`, default: `:LR`)

  ## Returns

  A string containing Mermaid graph syntax.
  """
  def graph(events, opts \\ []) do
    direction = Keyword.get(opts, :direction, :LR)

    # Group events by aggregate
    aggregates =
      events
      |> Enum.group_by(&{&1.aggregate_type, &1.aggregate_id})
      |> Enum.map(fn {{type, id}, agg_events} ->
        event_count = length(agg_events)
        node_id = sanitize_node_id("#{type}_#{id}")
        label = "#{type}<br/>#{id}<br/>(#{event_count} events)"
        {node_id, label, agg_events}
      end)

    nodes =
      aggregates
      |> Enum.map(fn {node_id, label, _} ->
        "    #{node_id}[\"#{label}\"]"
      end)

    # Create edges based on event relationships (simplified - connects aggregates that share event types)
    edges =
      aggregates
      |> Enum.flat_map(fn {node_id1, _, events1} ->
        aggregates
        |> Enum.filter(fn {node_id2, _, _} -> node_id1 != node_id2 end)
        |> Enum.flat_map(fn {node_id2, _, events2} ->
          shared_types =
            MapSet.intersection(
              MapSet.new(Enum.map(events1, & &1.event_type)),
              MapSet.new(Enum.map(events2, & &1.event_type))
            )

          if MapSet.size(shared_types) > 0 do
            ["    #{node_id1} --- #{node_id2}"]
          else
            []
          end
        end)
      end)
      |> Enum.uniq()

    ["graph #{direction}"]
    |> Kernel.++(nodes)
    |> Kernel.++(edges)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # Private helper functions

  defp format_date(nil, _format), do: "N/A"

  defp format_date(datetime, :short) do
    "#{datetime.year}-#{pad(datetime.month)}-#{pad(datetime.day)}"
  end

  defp format_date(datetime, :long) do
    "#{datetime.year}-#{pad(datetime.month)}-#{pad(datetime.day)} #{pad(datetime.hour)}:#{pad(datetime.minute)}"
  end

  defp format_date(datetime, :timestamp) do
    DateTime.to_unix(datetime) |> to_string()
  end

  defp pad(num) when num < 10, do: "0#{num}"
  defp pad(num), do: to_string(num)

  defp format_event_label(event, show_data, order_value, order_by) do
    base = "#{event.event_type}<br/>ID: #{event.aggregate_id}<br/>#{order_by}: #{order_value}"

    if show_data and event.data != %{} do
      data_preview =
        event.data
        |> Enum.take(2)
        |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
        |> Enum.join("<br/>")

      "#{base}<br/>#{data_preview}"
    else
      base
    end
  end

  defp format_timestamp(datetime) do
    "#{datetime.year}-#{pad(datetime.month)}-#{pad(datetime.day)} #{pad(datetime.hour)}:#{pad(datetime.minute)}:#{pad(datetime.second)}"
  end

  defp default_state_extractor(event) do
    # Try to extract state from event data, otherwise use event type
    case event.data do
      %{"status" => status} when is_binary(status) -> status
      %{status: status} when is_binary(status) -> status
      _ -> event.event_type |> String.split(".") |> List.last() |> String.capitalize()
    end
  end

  defp sanitize_node_id(str) do
    str
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end
end
