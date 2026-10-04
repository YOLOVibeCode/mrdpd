import CoreGraphics
import FrameKit

/// Startup lines for `mrdpd-serve` (T1-MON-02): every Mac display, the main one, the served one.
public enum DisplayListing {
    public static func lines(
        catalog: DisplayCatalog,
        served: DisplayCatalog.Entry,
        names: [UInt32: String],
        screensHaveSeparateSpaces: Bool
    ) -> [String] {
        var out = ["Mac displays, left to right:"]
        for entry in catalog.entries {
            let name = names[entry.displayID] ?? "Display \(entry.displayID)"
            let f = entry.frame
            var line = "  \(entry.letter)  \(name)  \(Int(f.width))x\(Int(f.height)) at (\(Int(f.minX)),\(Int(f.minY)))"
            var marks: [String] = []
            if entry.isMain {
                marks.append("main")
            }
            if entry.displayID == served.displayID {
                marks.append("serving")
            }
            if !marks.isEmpty {
                line += "  " + marks.joined(separator: ", ")
            }
            out.append(line)
        }
        if !served.isMain && !screensHaveSeparateSpaces {
            out.append(
                "warning: display \(served.letter) has no menu bar or Dock because \"Displays have separate Spaces\" is off"
                    + " (System Settings > Desktop & Dock)"
            )
        }
        return out
    }
}
