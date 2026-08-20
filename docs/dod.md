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

- [ ] Real engine dylib passes the **identical** ABI suite as StubEngine
- [ ] Headless client BMP matches the solid-color golden
- [ ] Spikes R1, R2, R5 written

## M6 extra (survival gate)

- [ ] iPad Windows App: live desktop + keyboard + mouse, documented in interop.md
- [ ] Accessibility + Screen Recording TCC onboarding path documented
- [ ] Traceability rows for T1 graphics + T1 input are at least `interop-green` on iPad

## M12 extra

- [ ] Clean VM / clean user install
- [ ] Launch Agent survives logout/login (not FileVault pre-boot)
- [ ] Notarized app + dylib
- [ ] FileVault limitation in user-facing docs
