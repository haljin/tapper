defmodule Tracer.Server.InitTest do
  use ExUnit.Case

  import Test.Helper.Server

  alias Tapper.Tracer
  alias Tapper.Tracer.Trace
  alias Tapper.Timestamp

  test "init, no options" do
    config = config()
    id = %{trace_id: trace_id, span_id: span_id} = Tapper.Id.test_id()
    timestamp = Timestamp.instant()

    {:ok, trace, ttl} = Tapper.Tracer.Server.init([config, id, false, self(), timestamp, []])

    assert trace.trace_id == trace_id
    assert trace.span_id == span_id
    assert trace.parent_id == :root
    assert trace.sample == true
    assert trace.debug == false

    assert trace.timestamp == timestamp
    assert trace.last_activity == timestamp
    assert trace.end_timestamp == nil

    assert ttl == 30_000
    assert ttl == trace.ttl

    assert is_map(trace.spans)
    assert Map.keys(trace.spans) == [span_id]
    span = trace.spans[span_id]

    assert span.id == span_id
    assert span.parent_id == :root
    assert span.start_timestamp == timestamp
    assert span.end_timestamp == nil
    assert span.name == "unknown"
    refute span.shared

    annotations = span.annotations
    assert is_list(annotations)
    assert length(annotations) == 1

    assert hd(annotations) == %Trace.Annotation{
        timestamp: timestamp,
        value: :cs,
        host: Trace.endpoint_from_config(config)
    }

    assert span.binary_annotations == []
  end

  test "init, ttl: ttl; sets ttl" do
    ttl = :rand.uniform(1000)

    config = config()
    id = Tapper.Id.test_id()
    timestamp = Timestamp.instant()

    {:ok, trace, ^ttl} = Tapper.Tracer.Server.init([config, id, false, self(), timestamp, [ttl: ttl]])

    assert trace.ttl == ttl
  end

  test "init, type: server; adds :sr annotation" do
    {trace, span_id} = init_with_opts(type: :server)

    span = trace.spans[span_id]

    refute span.shared, "expected server span not to be shared by default"

    annotations = trace.spans[span_id].annotations
    assert length(annotations) == 1

    assert hd(annotations) == %Trace.Annotation{
        timestamp: trace.timestamp,
        value: :sr,
        host: Trace.endpoint_from_config(trace.config)
    }

    assert span.binary_annotations == []
  end

  test "init, type: client; is not shared, adds :cs annotation" do
    {trace, span_id} = init_with_opts(type: :client)

    span = trace.spans[span_id]

    refute span.shared

    annotations = span.annotations
    assert length(annotations) == 1

    assert hd(annotations) == %Trace.Annotation{
        timestamp: trace.timestamp,
        value: :cs,
        host: Trace.endpoint_from_config(trace.config)
    }

    assert span.binary_annotations == []
  end

  test "init, type: client, remote: endpoint; adds server address binary annotation" do
    remote = random_endpoint()
    {trace, span_id} = init_with_opts(type: :client, remote: remote)

    span = trace.spans[span_id]

    refute span.shared

    annotations = span.annotations
    assert length(annotations) == 1

    assert hd(annotations) == %Trace.Annotation{
        timestamp: trace.timestamp,
        value: :cs,
        host: Trace.endpoint_from_config(trace.config)
    }

    binary_annotations = span.binary_annotations
    assert length(binary_annotations) == 1
    assert hd(binary_annotations) == %Trace.BinaryAnnotation{
        annotation_type: :bool,
        key: :sa,
        value: true,
        host: remote
    }
  end

  test "init, type: server, remote: endpoint adds client address binary annotation" do
    remote = random_endpoint()
    {trace, span_id} = init_with_opts(type: :server, remote: remote, shared: true)

    span = trace.spans[span_id]

    annotations = span.annotations
    assert length(annotations) == 1

    assert hd(annotations) == %Trace.Annotation{
        timestamp: trace.timestamp,
        value: :sr,
        host: Trace.endpoint_from_config(trace.config)
    }

    binary_annotations = span.binary_annotations
    assert length(binary_annotations) == 1
    assert hd(binary_annotations) == %Trace.BinaryAnnotation{
        annotation_type: :bool,
        key: :ca,
        value: true,
        host: remote
    }
  end

  test "init with name: name" do
    {trace, span_id} = init_with_opts(name: "name")

    assert trace.spans[span_id].name == "name"
  end

  test "init with name, then rename span" do
    {trace, span_id} = init_with_opts(name: "name")

    assert trace.spans[span_id].name == "name"

    timestamp = Timestamp.instant()

    {:noreply, state, _ttl} =
        Tapper.Tracer.Server.handle_cast({:update, span_id, timestamp, [Tracer.name_delta("new-name")]}, trace)

    assert state.spans[span_id].name == "new-name"
    assert state.last_activity == timestamp
  end

  test "init with annotations adds annotations" do
    {trace, span_id} = init_with_opts(name: "name", annotations: [
      Tracer.annotation_delta(:ws),
      Tracer.binary_annotation_delta(:double, "temp", 69.2)
    ])

    assert annotation_by_value(trace.spans[span_id], :ws)
    assert binary_annotation_by_key(trace.spans[span_id], "temp")
  end

  test "init with string annotations adds annotations" do
    {trace, span_id} = init_with_opts(name: "name", annotations: [
      Tracer.annotation_delta("something"),
      Tracer.binary_annotation_delta(:double, "temp", 69.2)
    ])

    assert annotation_by_value(trace.spans[span_id], "something")
    assert binary_annotation_by_key(trace.spans[span_id], "temp")
  end

  test "init with non-list annotations: adds annotation" do
    {trace, span_id} = init_with_opts(name: "name", annotations: Tracer.annotation_delta(:ws))

    assert annotation_by_value(trace.spans[span_id], :ws)
  end

  test "init with conflicting shortcut annotations still adds annotations" do
    alternative_endpoint = random_endpoint()
    {trace, span_id} = init_with_opts(name: "name", annotations: [
      Tracer.name_delta("foo"),
      Tracer.annotation_delta(:cs, alternative_endpoint)
    ])

    assert trace.spans[span_id].name == "foo"
    cs = annotation_by_value(trace.spans[span_id], :cs)
    assert cs
    assert cs.host == alternative_endpoint
  end

end
