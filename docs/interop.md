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

- TLS with generated cert; NLA username/password from a local test config (not the macOS login password)
- Bind `127.0.0.1` plus optional Tailscale IP; **never** advertise 3389 on a public interface in development
- Tunnel if needed: `ssh -N -L 3390:127.0.0.1:3389 …` as in the original notes

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
