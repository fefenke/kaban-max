# WARP runtime failures: implementation plan

Goal: restore visible runtime failures and fail over when the configured primary service fails on the active tunnel but works on a reserve. Preserve planned-shutdown suppression and bounded retries. Spec: user request2026-11-25 and [audit](../../WARP_LOGGING_AUDIT.md).

Execution: one assistant, no agents. Existing user changes are preserved. No publication requested in this turn. Local-router diagnosis is authorized; warn before any disruptive acceptance test.

- [x] Reproduce primary-only URL failure, shared URL outage, recovery and Warn visibility in Go regressions; demonstrate RED on current r41.
- [x] Add append-only core patch restoring significant runtime logs, preserving routine close classification, lifecycle scope and WAN noise bounds. Preserve the original WAN gate as explicitly clarified by the user; restore Applied target warning visibility.
- [x] Fix stable fallback with repeated same-target comparison rather than discarding primary failure after confirm success; preserve identity/cancellation/freshness guards and avoid switching to a reserve with the same failure.
- [ ] Diagnose the local first-tunnel Google failure at TCP/TLS/HTTP boundaries using bounded native probes; do not regenerate credentials or stop the service speculatively.
- [x] Run targeted race suites plus affected integration checks against pinned source+patches. Update current contracts, source facts and exact evidence. Build/install only if justified and safely recoverable; distinguish completed fixes from unresolved external causes.

- [x] Diagnose the additional Applied/Pending records and fix bounded failed-transport retry plus misleading healthy-source labels.
- [ ] Install the concrete verified 0.2.3/r42 package set only after explicit local-router installation approval; the user asked about contents instead of granting approval.
