# Architecture decision records

Numbered, immutable once accepted. New decision = new file. Supersede by adding `Supersedes: NNNN` in a later ADR.

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-swift-first-hybrid.md) | Swift-first hybrid with IronRDP engine | accepted |
| [0002](0002-c-abi-engine-boundary.md) | C ABI is the only engine interface | accepted |
| [0003](0003-tdd-and-isp.md) | TDD + ISP; grow protocols from tests | accepted |
| [0004](0004-single-console-session.md) | One logged-in user, one active client | accepted; "one active client" superseded by 0006 on merge |
| [0005](0005-private-virtual-display.md) | Flagged private virtual display; dummy plug fallback | accepted |
| [0006](0006-viewports.md) | Viewports: one console, many independent views | proposed |
| [0007](0007-h264-encode-scheduler.md) | H.264 for every viewport, behind an encode scheduler | proposed |
| [0008](0008-native-ipad-client.md) | Native iPad client over a native viewport protocol | proposed — owner decision |
| [0009](0009-reuse-not-fork.md) | Reuse upstream and prior art; do not fork macrdp | proposed |
