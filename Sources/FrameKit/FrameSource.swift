/// Producer of BGRA `Frame` values (T1-GFX-01, B3).
///
/// Only `nextFrame()` exists: that is all `SyntheticFrameSource`, `SCKFrameSource`, and the contract suite call.
/// Encode, audio, monitor list, and H.264 are not part of this protocol.
public protocol FrameSource: Sendable {
    func nextFrame() async -> Frame
}
