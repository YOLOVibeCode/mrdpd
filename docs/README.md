# mrdpd documentation

This folder is the project memory. Chat is not. If it is not in one of these files, it did not happen.

## Read order (new session)

1. [AGENTS.md](../AGENTS.md) — rules that bind every coding session
2. [method.md](method.md) — TDD + ISP, constituents forward
3. [spec.md](spec.md) — what we are building (requirement IDs)
4. [architecture.md](architecture.md) — how the pieces fit
5. [traceability.md](traceability.md) — every ID mapped to a test and a milestone
6. [abi.md](abi.md) — C engine boundary semantics (write tests from this, not from vibes)
7. [dod.md](dod.md) — when a milestone is actually done
8. [milestones.md](milestones.md) — M0–M12 gates
9. [modules.md](modules.md) — constituent build order
10. [tasks/m0.md](tasks/m0.md) — the only work that is decomposed today
11. [workstreams.md](workstreams.md) — how to run several agents without collisions

## Map

| File | Purpose |
| --- | --- |
| [spec.md](spec.md) | Functional specification with stable requirement IDs |
| [milestones.md](milestones.md) | Implementation gates M0–M12 |
| [modules.md](modules.md) | Constituent modules and extract-later protocols |
| [method.md](method.md) | TDD, ISP, elements-forward build order |
| [architecture.md](architecture.md) | Modules, boundaries B1–B6, growth rules |
| [abi.md](abi.md) | C ABI contract: threads, ownership, errors, versioning |
| [traceability.md](traceability.md) | Requirement → contract test → E2E → interop → milestone |
| [dod.md](dod.md) | Milestone definition of done |
| [risks.md](risks.md) | Open risks and spikes |
| [interop.md](interop.md) | Client matrix and per-milestone manual gates |
| [glossary.md](glossary.md) | Terms |
| [adr/](adr/) | Architecture decision records |
| [tasks/](tasks/) | Rolling-wave task lists (only current + next milestone) |
| [spikes/](spikes/) | Spike findings (empty until M1) |
| [workstreams.md](workstreams.md) | Parallel agent lanes and file locks |
| [agents/](agents/) | Copy-paste briefs (one stream per chat) |
| [req.txt](req.txt) | Original conversation that motivated the project (historical) |

## What “success” means here

A requirement is not done because someone implemented it. It is done when its row in [traceability.md](traceability.md) is `interop-green` (or `accepted-out` for non-goals). Empty cells are bugs in the plan, not optional homework.
