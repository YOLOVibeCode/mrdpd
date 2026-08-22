# Spikes

Drop findings here using the template in [risks.md](../risks.md).

## M1 (required — done)

| Risk | File | Answer |
| --- | --- | --- |
| R1 | [2026-08-20-r1-static-multimon.md](2026-08-20-r1-static-multimon.md) | Static GCC multimon **not** implemented server-side. T2-MON-01 = upstream/acceptor patch at M9, not OUT. |
| R2 | [2026-08-20-r2-rdpei.md](2026-08-20-r2-rdpei.md) | `RdpeiServer` exists; `ironrdp-server` does not attach it. T2-IN-03 = upstream PR; T1 wheel fallback. |
| R5 | [2026-08-20-r5-reconnect-cookies.md](2026-08-20-r5-reconnect-cookies.md) | Cookie API on IronRDP **master**, not crates.io 0.13.0. T2-SEC-01 after M6; not OUT. |
