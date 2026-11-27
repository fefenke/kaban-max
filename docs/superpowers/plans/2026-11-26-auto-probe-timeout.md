# Align automatic probe and fallback timeouts

User request2026-11-26: explain and fix the5s probe versus8s configured fallback mismatch when necessary. Local changes/tests only; installation approval remains pending.

Contract: preserve default5s for routes without a declared fallback budget. For a configured fallback, include its TCP candidate-attempt budget plus5s for verified TLS/HTTP. Follow the selected group chain with a bounded depth; never extend the parent60s job deadline. Preserve identity/policy guards and two independent verified application attempts.

- [x] Read current webAttempt and fallback newAttempt; confirm the outer5s timer can cancel before8s configured dial completes.
- [x] Add a real delayed-dial/TLS/HTTP regression and a shorter parent-deadline regression.
- [x] Run RED on unchanged r42. First Docker execution was not executed: automatic approval review failed with HTTP403, not a safety finding.
- [x] Add a probe-budget method on fallback and bounded timeout selection through the chosen group chain; keep direct default5s.
- [x] Run targeted autoroute/group race tests and clean patch application; build and package the next local core revision, retaining app0.2.3.
- [x] Update exact evidence/current contracts and run the documentation gate. Do not mark an unrun test as passing or install without approval.

Additional explicit user scope: default-off TCP-only unconfirmed-protocol consent below IP-only, truthful weak evidence, unchanged known TLS/UDP/scope guards; Applied shows rule state with retained error history and no new per-IP follow-up jobs. Existing unconfirmed Pending is reconsidered after opt-in Save & Apply; successful retained results are not rerun.
