# Interop gates

Automated tests prove contracts. These checklists prove Windows App will actually connect.

## Reference clients

| Client | Role | Used for |
| --- | --- | --- |
| IronRDP headless | CI | Handshake, BMP goldens, scripted input (M1+) |
| FreeRDP (`xfreerdp` / SDL) | CI/manual | Second independent stack |
| Windows App iPadOS | **Primary T1** | Survival gate M6; every T1 milestone after M2 |
| Windows App macOS/Windows | T2 multimon | M9 |

## Default connection

Until M12 distribution exists:

- TLS with generated cert; NLA username `mrdpd` / password `changeme` (lab only, gitleaks-allowlisted; not the macOS login password)
- Bind `127.0.0.1` plus optional Tailscale IP; **never** advertise 0.0.0.0. `mrdpd-pattern` and `mrdpd-serve` exit 4 on unspecified bind (T1-SEC-04)
- Tunnel if needed: `ssh -N -L 3390:127.0.0.1:3389 …` as in the original notes

### M2 lab server (1080p quadrants)

```bash
just serve-pattern
# iPad / other host: just serve-pattern host=<tailscale-ip>
```

Connect: `127.0.0.1:3390`, NLA `mrdpd` / `changeme`, expect four quadrants (red / green / blue / white). FreeRDP example:

```bash
xfreerdp /v:127.0.0.1:3390 /u:mrdpd /p:changeme /cert:ignore /rfx /size:1920x1080
# macOS Homebrew (no XQuartz): just test-freerdp
#   sdl-freerdp + SDL_VIDEODRIVER=dummy; asserts GDI PIXEL_FORMAT_BGRA32
```

### M5 lab server (live desktop)

Needs Screen Recording TCC (`docs/tcc.md`).

```bash
just serve
# iPad / other host: just serve host=<tailscale-ip>
```

Same NLA. Expect the Mac console (cursor composited). Keyboard and mouse inject via Accessibility TCC (`CGEventInputSink`).

## Per-milestone manual gates

| After | iPad Windows App | FreeRDP | Desktop Windows App |
| --- | --- | --- | --- |
| M2 | solid / gradient test pattern visible | same | optional |
| M5 | live desktop, view only, note FPS | same | optional |
| M6 | type a paragraph, Cmd-shortcuts, mouse | same | optional |
| M7 | copy/paste text both ways | same | optional |
| M8 | rotate iPad / change resolution | `/dynamic-resolution` | optional |
| M9 | informative only (single monitor) | layout if supported | **required**: 2 monitors, add/remove |
| M10 | WAN smoke if possible | A/B notes | optional |
| M11 | hear tone / system audio | same | optional |
| M12 | clean install path | — | — |

Deferral requires a sentence in the milestone notes (client missing, lab down). Silent skip fails DoD.

## Recording a run

Append a short note to `docs/tasks/mN.md`:

```markdown
## Interop log
- Date:
- Client + version:
- Host macOS:
- Result: pass / fail
- Evidence (screenshot path or description):
- Follow-up IDs:
```
