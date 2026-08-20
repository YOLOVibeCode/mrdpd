/// Consumer of engine-delivered input (T1-IN-01). ISP: `handle` only.
public protocol InputSink: AnyObject {
    func handle(_ event: InputEvent)
}
