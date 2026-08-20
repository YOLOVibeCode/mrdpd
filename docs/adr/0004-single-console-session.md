# ADR 0004: Single console session, one active client

Status: accepted  
Date: 2026-08-20

## Context

Windows multi-session RDP is not a macOS capability. ScreenCaptureKit and CGEvent target the logged-in GUI session.

## Decision

mrdpd mirrors **one** console user. T1 allows one active client; a second connection is rejected or waits (exact policy implemented under T1-SEC-03 tests). Optional T2 read-only shadowing is out of the M0–M6 path.

We will not attempt login-window, Fast User Switching hosts, or FileVault pre-boot (OUT-02, OUT-03).

## Consequences

- Launch Agent, not system daemon.
- Repair-shop story still requires FileVault unlock by a human.
- Simpler session and NLA model.
