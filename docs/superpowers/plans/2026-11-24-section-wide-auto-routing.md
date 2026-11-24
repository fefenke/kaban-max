# Applied IP routes across the selected section

Explicit user clarification 2026-11-24: applying an IP must cover all devices of the selected section; the uncovered-connections status must disappear. Migrate already approved records. Preserve section/IP ownership, first-match policy, infrastructure protection and explicit exclusions. Source remains pinned upstream plus patches. Solo execution.

- [x] Diagnose live state read-only: source enabled, no pressure; applied records on different LAN devices than new errors. Reproduce pending rows hidden merely by matching IP.
- [x] Add RED core test for other-device matching and backend test for hidden Pending.
- [x] Implement r39 `all_devices` for persistent web IP approvals, migration/deduplication on restore, actual-flow exclusion checks, backend compact/remember/action support and remove the UI status.
- [x] Verify clean patch matrix, frontend/build, backend suite and documentation.
- [x] Build/install preview through stock installer, warning before its automatic restart; verify old approvals now cover the affected device without granting another section or IP. Keep flash staging clean.

Evidence: [preview 0.2.9/r39](../../PREVIEW_029.md). Two old approvals migrated; actual live flows for their IPs were absent from the post-install connection snapshot, so packet-level coverage is not claimed. No publication.

Ruling: strict short-lived application decisions and device-scoped exclusions retain their existing scope. Persistent web IP approvals are section-wide. Origin device/inbound fields remain attestation metadata, not routing restrictions. Backend hides only errors actually covered by a lease, so legacy narrow grants cannot hide actionable errors on another device.
