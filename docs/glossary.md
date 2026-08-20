# Glossary

| Term | Meaning |
| --- | --- |
| mrdpd | This project: a macOS RDP server daemon / app |
| Engine | The RDP protocol implementation behind the C ABI (IronRDP today; swappable) |
| StubEngine | Test-double dylib that implements `mrdpd_engine.h` deterministically |
| B1–B6 | Named module boundaries; see architecture.md |
| T1 / T2 / T3 | Spec tiers: core session / desktop parity / device redirection |
| OUT | Explicit non-goal |
| NLA | Network Level Authentication (CredSSP), required by Windows App by default |
| EGFX | MS-RDPEGFX graphics pipeline (H.264) |
| RemoteFX | Bitmap codec used as T1 default / T2 fallback |
| RDPEDISP | Dynamic monitor layout channel |
| SCK | ScreenCaptureKit |
| TCC | Transparency, Consent, and Control (macOS permission prompts) |
| ISP | Interface Segregation Principle |
| Contract suite | Tests that take any conformer of a protocol / any ABI dylib |
| Survival gate | M6: live screen + input from iPad; T2 work waits for this |
| Rolling-wave | Only the current and next milestone are fully tasked |
