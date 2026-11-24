# Release 0.2.3: retained routing diagnostics

User scope 2026-11-24: fix retained Applied errors/domain labels, install current fixed code under public version 0.2.3 and publish to GitHub. Public latest is 0.2.2; higher versions were private previews. Explicit clarification: sanitize new release/current files only, preserve published history/tags.

- [x] RED tests: retained diagnostics across compact intent/reload; no flash dirtiness; domain-label carry-forward, ownership/memory bounds; meaningful UI and no empty Error.
- [x] Bounded RAM diagnostic sidecar joined only to the exact approved record. Keep original source failure distinct from later target failures. Keep compact route permissions/flash schedule unchanged.
- [x] Core preserves original failure and observed labels during replacement; UI renders readable timeout wording and raw technical details, honest missing legacy information.
- [x] Validate source/CI suites, release source and 10 packages; publishable files/commit metadata/assets scanned for secrets, personal data and unwanted tool mentions. Preserve upstream license notices and synthetic test values. Preserve local private evidence outside publication.
- [x] Install numeric 0.2.3 with fresh core through stock installer (supported downgrade handling if needed), autonomous restart, targeted backup, native state/HTTPS/retention checks and staging cleanup.
- [ ] Publish sanitized current source with nonpersonal commit metadata and tag 0.2.3, release notes/assets/GPL source; verify remote refs/assets/checksums and update authoritative state.

No extra approval needed for install/publish: both explicitly requested. Do not force-push history. Private .local, real configs/logs, local paths and audit transcripts are excluded from publication. Existing public history may still contain old mentions per user's decision.
