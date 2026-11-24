# Persistent WARP port hints

**Goal:** Preserve a working local UDP port per native WARP profile across router reboot without routine flash writes.

Agreed 2026-11-24: existing port works → zero writes. A replacement requires an authenticated handshake, received IP data and ten continuous healthy minutes. Maximum one changed-port save per profile per router boot; switching profiles and restarting KabanMax do not reset that allowance. Server port and explicit bind behavior remain unchanged. This plan is executed inline by the current assistant only.

- [x] Add failing backend tests for unchanged hints, ten-minute delay, failure/reset, separate profiles, process restart, per-boot write cap and profile ownership.
- [x] Add a reproducible core patch exposing authenticated, read-only WARP path status and accepting a soft configuration hint when RAM cache is absent; cover with focused Go tests.
- [x] Persist hidden UCI hint fields through a fresh isolated cursor, under the lifecycle lock, only when eligible. Keep timers/allowance in `/var/run`, never in flash. Batch eligible profiles into one commit. Never trigger a reload for a hint save.
- [x] Run focused tests, clean patch application, affected backend suite and documentation gates. Update state and WARP contract with exact commands, date, outcomes and limitations.

Completed locally 2026-11-24. Clean apply 38 patches, four focused Go race packages, cmd compile, backend 98/98, docs 9/9/gate and diff check passed. See [evidence and limits](../../WARP_PORT_HINTS.md). Subsequent explicit install request fulfilled with preview 0.2.8/r38; see [installation evidence](../../PREVIEW_028.md). No publication.

Ruling: a boot which runs the existing saved port successfully for ten minutes also closes its save allowance using RAM only. This prevents a later mid-session change from writing flash after an already successful boot. Configured profile ID binds the hint; exact runtime/current UCI credentials plus response profile ID establish capture ownership. A core/bind instance change resets the stability interval.

Implementation choices: poll once per minute using the existing resident service timer; no active probes or traffic generation. A stale handshake, changed port, changed core instance or failed status request resets the stability window. Received IP data excludes WireGuard keepalive packets. A newer RAM hint may be reused on service restart; the persistent hint bootstraps an empty cache. Only generated native profiles with explicit credentials are eligible for durable hints. Profile identity and running config must match current UCI before a commit. Router installation/reboot is separate from local implementation and requires current authorization under AGENTS.md.
