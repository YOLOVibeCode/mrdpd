/// Test-double InputSink: records events for the contract suite (T1-IN-01).
public final class RecordingInputSink: InputSink {
    public private(set) var events: [InputEvent] = []

    public init() {}

    public func handle(_ event: InputEvent) {
        events.append(event)
    }
}
