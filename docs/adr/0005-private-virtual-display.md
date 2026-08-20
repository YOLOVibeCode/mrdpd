# ADR 0005: Private virtual display, dummy plug fallback

Status: accepted  
Date: 2026-08-20

## Context

Lid-closed and “client wants 2×1440p but the Mac has one panel” need extra framebuffers. `CGVirtualDisplay` / related private APIs are used by BetterDisplay and similar tools. They can break on OS updates and block App Store.

A $10 HDMI dummy plug creates a real extra display without private API.

## Decision

- Virtual display is **T2**, feature-flagged, off by default in release until proven.
- Document dummy plug as the supported headless path.
- App Store is OUT-05.
- Spike/confirm API on the then-current macOS at M9; if broken, flag stays off.

## Consequences

- Notarization risk if the private API is detected — R13.
- iPad (single monitor) does not need this for T1; dynamic resize (T1-MON-01) does.
