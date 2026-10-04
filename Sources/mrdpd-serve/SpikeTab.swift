import FrameKit
import Foundation
import InputKit

/// Spike R15 (branch `spike-r15-tab`, never merged): a static translucent tab drawn onto every
/// frame, to see whether each client's own chrome covers it. Off unless `MRDPD_SPIKE_TAB=1`.
/// `MRDPD_SPIKE_TAB_POS=center|left|right`, `MRDPD_SPIKE_TAB_WIDTH` (% of width, default 10),
/// `MRDPD_SPIKE_TAB_Y` (pixels down from the top edge, default 0).
struct SpikeTab: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    static func fromEnvironment(frameWidth: Int, frameHeight: Int) -> SpikeTab? {
        let env = ProcessInfo.processInfo.environment
        guard env["MRDPD_SPIKE_TAB"] == "1" else {
            return nil
        }
        let percent = Double(env["MRDPD_SPIKE_TAB_WIDTH"] ?? "") ?? 10
        let width = min(frameWidth, max(48, Int(Double(frameWidth) * percent / 100)))
        let height = min(frameHeight, max(28, frameHeight * 22 / 1000))
        let top = max(0, min(frameHeight - height, Int(env["MRDPD_SPIKE_TAB_Y"] ?? "") ?? 0))
        let left: Int
        switch env["MRDPD_SPIKE_TAB_POS"] ?? "center" {
        case "left": left = 0
        case "right": left = frameWidth - width
        default: left = (frameWidth - width) / 2
        }
        return SpikeTab(x: left, y: top, width: width, height: height)
    }

    func contains(x px: Int32, y py: Int32) -> Bool {
        Int(px) >= x && Int(px) < x + width && Int(py) >= y && Int(py) < y + height
    }

    func draw(into frame: Frame) -> Frame {
        var pixels = frame.pixels
        let stride = Int(frame.stride)
        let x0 = max(0, x)
        let y0 = max(0, y)
        let x1 = min(Int(frame.width), x + width)
        let y1 = min(Int(frame.height), y + height)
        guard x0 < x1, y0 < y1 else {
            return frame
        }
        func blend(_ px: Int, _ py: Int, gray: Double, alpha: Double) {
            let i = py * stride + px * 4
            for c in 0..<3 {
                pixels[i + c] = UInt8(Double(pixels[i + c]) * (1 - alpha) + gray * alpha)
            }
        }
        for py in y0..<y1 {
            for px in x0..<x1 {
                let edge = px == x0 || px == x1 - 1 || py == y1 - 1 || (y0 > 0 && py == y0)
                blend(px, py, gray: edge ? 200 : 34, alpha: edge ? 0.8 : 0.6)
            }
        }
        let gripWidth = min(28, (x1 - x0) / 3)
        let gripX = (x0 + x1) / 2 - gripWidth / 2
        let mid = (y0 + y1) / 2
        for offset in [-6, 0, 6] {
            for t in 0..<2 where (y0..<y1).contains(mid + offset + t) {
                for px in gripX..<(gripX + gripWidth) {
                    blend(px, mid + offset + t, gray: 230, alpha: 0.9)
                }
            }
        }
        let rect = Rect(x: Int32(x0), y: Int32(y0), width: UInt32(x1 - x0), height: UInt32(y1 - y0))
        return Frame(
            width: frame.width,
            height: frame.height,
            stride: frame.stride,
            pixels: pixels,
            dirtyRects: frame.dirtyRects + [rect]
        )
    }
}

/// Draws the spike tab onto every frame from `inner`.
final class SpikeTabFrameSource: FrameSource, @unchecked Sendable {
    private let inner: any FrameSource
    private let tab: SpikeTab

    init(inner: any FrameSource, tab: SpikeTab) {
        self.inner = inner
        self.tab = tab
    }

    func nextFrame() async -> Frame {
        tab.draw(into: await inner.nextFrame())
    }
}

/// Logs when the pointer reaches the spike tab and when a button goes down inside it.
/// Forwards every event unchanged: the spike consumes nothing.
final class SpikeTabInputSink: InputSink {
    private let inner: any InputSink
    private let tab: SpikeTab
    private var buttons: UInt32 = 0
    private var over = false

    init(inner: any InputSink, tab: SpikeTab) {
        self.inner = inner
        self.tab = tab
    }

    func handle(_ event: InputEvent) {
        if case let .mouse(x, y, buttons, _) = event {
            let inside = tab.contains(x: x, y: y)
            if inside && !over {
                fputs("R15: pointer over tab at (\(x),\(y))\n", stderr)
            }
            if inside && buttons != 0 && self.buttons == 0 {
                fputs("R15: click inside tab at (\(x),\(y))\n", stderr)
            }
            over = inside
            self.buttons = buttons
        }
        inner.handle(event)
    }
}
