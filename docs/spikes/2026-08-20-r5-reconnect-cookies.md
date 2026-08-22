# Spike R5: Auto-reconnect cookies

Date: 2026-08-20
Question: Does IronRDP **server** issue and validate MS-RDPBCGR 2.2.4.2 / 2.2.4.3 auto-reconnect cookies, or will a dropped iPad Wi-Fi force a full NLA?
Build / version of IronRDP: crates.io `ironrdp-server` **0.13.0** (what M1 pins) vs Devolutions/IronRDP `master` (`builder.rs`, `server.rs`); client notes in `ironrdp-client` / `ironrdp-web`.
What we ran: source inspection of both trees.
Evidence (logs, PDUs, links):

- **crates.io 0.13.0 (M1 pin): no cookie API.** Grep of `with_auto_reconnect_cookie` / `auto_reconnect` in the published crate is empty. That crate is also missing `ConnectionInfo` and related master-only builder flags. Do not assume crates.io 0.13.0 == git `master` even though both report version 0.13.0.
- **Server on `master` (yes):** `RdpServerBuilder::with_auto_reconnect_cookie` and `RdpServer::set_auto_reconnect_cookie` provision `ARC_SC_PRIVATE_PACKET`. After activation the server can send Save Session Info with the cookie; it validates `ARC_CS_PRIVATE_PACKET` (HMAC-MD5 per 5.5), rotates CSPRNG random per connection, updates the active client hourly, and keeps one previous cookie for the write-race window. Requires TLS or Hybrid (all-zero client random for Enhanced RDP Security). `None` (default) sends no cookie. A valid cookie **bypasses** `CredentialValidator` on TLS-mode reconnects (documented on the builder).
- **Our headless client (no):** `crates/ironrdp-client/src/rdp.rs` still has `TODO(#271)` — cookie field exists, automatic reconnect is not implemented. `ironrdp-web` logs the cookie and does not reconnect. The screenshot example does not send `ARC_CS_PRIVATE_PACKET`.
- **Windows App:** not verified in this spike (needs interop). Cookie support in mstsc / Windows App is the usual client path; IronRDP’s client gap does not block **our** server from issuing cookies once we are on an IronRDP that has the API.

Answer: **Implement after M6, not OUT** — but M1 cannot turn cookies on: crates.io 0.13.0 has no builder for them. Enabling T2-SEC-01 means bumping `ironrdp-server` to a crates.io release (or git pin) that includes `with_auto_reconnect_cookie`, then a contract that a second connect with the cookie skips password prompts on a cookie-capable client (C-IPAD / C-DESK). C-HEADLESS cookie tests wait on IronRDP client #271. M1 stays full NLA every connect.
Effect on spec / M9 / M10: T2-SEC-01 stays T2, milestone “M1 spike; feature TBD” → feature **after M6** once the engine crate is new enough. No spec ID change. No git pin of IronRDP `master` in M1 (API drift: `ConnectionInfo`, `honor_client_desktop_size` type, cookie builder).
Follow-up: Optional one-line enable in `mrdpd-engine` behind config (ABI v2 or app config at M12 — do not add a v1 ABI field for this). Track IronRDP #271 only for C-HEADLESS cookie tests.
