# Definition of done

A milestone is not done when the demo looks good. It is done when this list is true.

## Every milestone

- [ ] Every new or changed requirement ID has a contract-test path in [traceability.md](traceability.md)
- [ ] The same contract suite is green on the stub and, if a real implementation shipped, on the real implementation
- [ ] `just test` is green (TCC-free)
- [ ] E2E harness updated, or marked N/A on the milestone task list with a reason
- [ ] Interop checklist in [interop.md](interop.md) run or deferred with a named reason
- [ ] ABI / protocol diffs reviewed for ISP (no unused methods “for later”)
- [ ] Spike findings written under [spikes/](spikes/) if any spike ran
- [ ] `traceability.md`, `spec.md`, and ADRs updated in the same change set
- [ ] After M6 exists: no T2 feature merged unless M6 is interop-green or the change unblocks a T1 defect

## M0 extra

- [x] All files listed in [tasks/m0.md](tasks/m0.md) exist
- [x] `just test` runs Swift contract tests + StubEngine ABI tests with **zero** IronRDP
- [x] Smoke: EngineKit + StubEngine + SyntheticFrameSource + RecordingInputSink

## M1 extra

- [x] Real engine dylib passes the **identical** ABI suite as StubEngine
- [x] Headless client BMP matches the solid-color golden
- [x] Spikes R1, R2, R5 written

## M2 extra

- [x] `SyntheticFrameSource.pattern1080p` + EngineKit poison-after-return (ABI v1 only)
- [x] Headless 1080p quadrant BMP (RemoteFX, documented tolerance)
- [x] Lab process `mrdpd-pattern` (`just serve-pattern`) on 127.0.0.1; refuses 0.0.0.0
- [x] FreeRDP 3.30 `sdl-freerdp` GDI BGRA32 (`just test-freerdp`; ignored in `just test`)
- [ ] iPad Windows App shows the pattern (`docs/interop.md`; no device in this environment)

## M3 extra

- [x] US keymap table (T1-IN-02); `InputSink` still `handle` only
- [x] Headless FastPath sequence → ABI `on_key` / `on_mouse` (T1-IN-01 / T1-IN-03 pixels)
- [x] Sequence in `RecordingInputSink` via EngineKit hop; no CGEvent

## M4 extra

- [x] `DirtyRects` clip + empty → full frame; BGRA copy with stride (TCC-free)
- [x] `SCKFrameSource` passes `testFrameSourceContract` under `just test-local`
- [x] Screen Recording TCC documented (`docs/tcc.md`); CI never grants

## M5 extra

- [x] `FramePacer` 60 fps cap; `FramePump` over ABI v1; cursor default on (`SCKSettings`)
- [x] `mrdpd-serve` (`just serve`) on 127.0.0.1; refuses 0.0.0.0
- [x] `just bench` T1-PERF-01 pacer; T1-PERF-03/04 documented skip + [bench.md](bench.md)
- [x] FreeRDP GDI BGRA32 against live `mrdpd-serve` (3360×1890)
- [x] iPad Windows App live desktop view (`docs/interop.md`; 2026-08-21: rendered 3360×1890; not smooth)

## M6 extra (survival gate)

- [x] `DisplayMap` Retina/origin; `InjectionPlan`; `CGEventInputSink` (`InputSink.handle` only)
- [x] `mrdpd-serve` posts HID; Accessibility documented (`docs/tcc.md`); CI never grants
- [x] iPad Windows App: live desktop visible; some typing (`docs/tasks/m6.md` C-IPAD log). Smoothness + full mouse/Cmd still open
- [ ] Traceability rows for T1 graphics + T1 input are at least `interop-green` on iPad

## M12 extra

- [ ] Clean VM / clean user install
- [ ] Launch Agent survives logout/login (not FileVault pre-boot)
- [ ] Notarized app + dylib
- [ ] FileVault limitation in user-facing docs
