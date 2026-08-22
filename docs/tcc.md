# TCC (T1-OPS-03)

CI never grants or simulates TCC (`AGENTS.md`). `just test` is TCC-free.

## Screen Recording (M4 / M5 / M6)

`SCKFrameSource` and `mrdpd-serve` need **Screen Recording**.

Grant: System Settings → Privacy & Security → Screen Recording → enable the terminal or Xcode that runs `just test-local` or `just serve`.

```bash
just test-local
just serve
```

`just test-local` sets `MRDPD_TEST_LOCAL=1`. Without the env var, SCK and CGEvent post tests **skip**. With the env var and no grant, they **fail** (do not silent-skip).

`CGPreflightScreenCaptureAccess()` is the Screen Recording check. Do not call `CGRequestScreenCaptureAccess()` from CI.

## Accessibility (M6)

`CGEventInputSink` and `mrdpd-serve` input need **Accessibility**.

Grant: System Settings → Privacy & Security → Accessibility → enable the same terminal or Xcode.

`AXIsProcessTrusted()` is the check. Do not prompt (`AXIsProcessTrustedWithOptions`) from CI.

If Accessibility is missing, `mrdpd-serve` prints `T1-OPS-03: Accessibility TCC missing; see docs/tcc.md` and exits 1. It does not fall back to a recording sink.

## FileVault

Pre-boot has no network. Documented as OUT; do not fight it.
