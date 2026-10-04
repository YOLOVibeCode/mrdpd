# mrdpd for iPad

The native client ([ADR 0008](adr/0008-native-ipad-client.md)): each app window is one **viewport** onto one Mac display ([ADR 0006](adr/0006-viewports.md)). Put one window on the iPad screen and another on the external 4K monitor (Stage Manager) and they show two different Mac displays at once, each switchable on its own.

## What it does

| Area | What you can do |
| --- | --- |
| Screens | One window per Mac display. **New Window** opens another, which picks a display no other window shows. |
| Switching | Ctrl+Option+1…9 picks display N (numbered top→bottom or left→right). Ctrl+Option+[ and ] step through them, and Ctrl+Option+0 opens the picker. You can also tap the pill at the top (‹ name ›) or three-finger tap. |
| Keyboard | Mac-correct: Cmd is Cmd and Option is Option (keys travel as HID codes, not Windows shortcuts). Held keys repeat at the Mac's own rate. |
| Trackpad / mouse | Click and secondary click, drag, and smooth scrolling with phases and momentum. The **Mac cursor** is drawn on the iPad at your pointer, with no video lag. |
| Touch | Tap = click, long press = right click, one-finger drag = drag, two-finger pan = scroll. |
| Picture | H.264 per window at the window's own resolution and the display's aspect ratio. iPadOS decodes it in hardware. |

## Set up (once)

1. **Mac**, in a Terminal that has Screen Recording and Accessibility ([tcc.md](tcc.md)):

   ```bash
   just host-serve 100.x.y.z        # your Mac's Tailscale IP (or LAN IP); never 0.0.0.0
   ```

2. **Mac**, second Terminal:

   ```bash
   just host-pair 100.x.y.z name="iPad Pro"
   ```

   This prints a QR code and puts an `mrdpd://pair?…` link on the Mac's clipboard. The link is a secret key for that one iPad.
3. **Install the app** with the iPad connected by USB (or paired in Xcode → Devices for Wi-Fi). Developer Mode must be on (Settings → Privacy & Security). Then run:

   ```bash
   just ipad-device                 # team defaults to N42FM5L5KD; pass team=<id> for another
   xcrun devicectl device install app --device "<iPad name>" .build/ipad/Build/Products/Release-iphoneos/mrdpd.app
   ```

   Or open `apps/ipad/mrdpd-ipad.xcodeproj` (after `just ipad-project`) in Xcode, pick the iPad, and Run.
4. **iPad**: open mrdpd and tap **Paste** (Universal Clipboard brings the link over), or scan the QR code with the Camera app and confirm the Mac's name and address.

## Two screens at once

1. Turn on Stage Manager on the iPad and connect the 4K monitor by USB-C.
2. In mrdpd, tap the pill → **⋯ → New Window**. Drag the new window to the external display and maximize it.
3. Switch either window independently. The window you are using gets 60 fps; on an M4 Max both get 60 fps (two hardware encoders). A third window drops the less-recently-used ones to 30 fps ([spike R15](spikes/2026-10-04-r15-encode-budget.md)).

## Security

- Each iPad has its own random 32-byte key, generated on the Mac. The connection is TLS 1.2 ECDHE-PSK with ChaCha20-Poly1305, so it has forward secrecy and needs no certificates. A wrong or unknown key fails the handshake.
- The host listens on one explicit address only. `mrdpd-host devices` lists paired iPads, and `mrdpd-host unpair <id>` revokes one immediately (the running host reloads keys within 2 s).
- The pairing link is the key: it is shown once, and you should not paste it anywhere else. `mrdpd-host pair` never prints it as text unless you ask with `--print-link`.
- On the iPad, keys live in the Keychain (this device only). On the Mac they live in `~/Library/Application Support/mrdpd/devices.json` (mode 0600) until the host ships as a signed app (M12, T1-SEC-07).
- The app confirms before pairing from a scanned or opened link, so a malicious link cannot quietly add a fake "Mac".

## Known limits (v0.1)

- **Keyboard shortcuts.** iPadOS keeps Cmd+Tab, Cmd+Space, and Globe shortcuts for itself. macOS also ignores synthetic Cmd+Tab and Spotlight (R18).
- **Typing** needs a hardware keyboard (Magic Keyboard or Bluetooth); the on-screen keyboard is not wired up yet.
- **Clipboard** uses Universal Clipboard (same Apple ID): copy on one side, paste on the other. There is no in-app clipboard channel yet.
- **Sharpness on a 4K window.** It is streamed at up to ~5.7 Mpx so it stays at 60 fps, then scaled up slightly. A sharper tiled mode is planned ([ADR 0007](adr/0007-h264-encode-scheduler.md)).
- **No audio.** The host runs from a Terminal (no menu-bar app or Launch Agent yet), and synthetic input cannot reach the Mac's login window.

## How it fits together

```text
iPad window ──TLS-PSK/TCP──▶ mrdpd-host (HostKit)
  ViewportClient                NativeServer → ViewportSession per window
  H264SampleBuilder               DisplayRegistry · SCK capture at window size · H.264 (VideoToolbox)
  AVSampleBufferDisplayLayer      EncodeScheduler · NativeInputInjector (CGEvent) · CursorMonitor
```

The wire format, messages, geometry, pairing, and shortcuts live in `Packages/ViewportKit` and are shared by both ends.

## Tests

| Command | What it proves |
| --- | --- |
| `just test` | Protocol and transport contracts. Host unit tests. Loopback end to end with real TLS and real H.264: main display, switching, click mapping, thumbnails, resize, two windows at once, unpaired key refused, new pairing without restart. |
| `just ipad-sim-check` | The real app in an iPad Pro 13" simulator against a real host. A tap arrives as a click, a long press as a right click, a drag moves the pointer, and HID keys arrive with a real Cmd. Ctrl+Option+1/2 switch displays and never reach the Mac. Input is logged, not posted (`--no-inject`). |
