# Auto-routing storage implementation plan

Goal: retain compact routing grants/exclusions, clean expendable diagnostics, replace record-count limits with byte budgets, checkpoint changed intents daily by default.

Architecture: keep existing atomic applied/excluded files and source/device/inbound guards. Runtime metadata remains private and RAM-only. Core admission uses conservative accounted memory bytes, never total process RSS as an autoroute-only guarantee. Backend bounds compact serialized storage below the configured budget to reserve space for parsing/copies.

Execution: inline, no agents, no commits/deployment. Existing r23 fixes remain intact. The user explicitly requested completion after discussing the design; no additional design approval round.

Settings: save interval `1d` (15m–30d), transient retention `1h` (1m–7d), memory budget `4` MiB (1–32). All are global; byte budgets must agree across backend/core. Actual process memory includes other subsystems and temporary allocations.

- [x] Add backend settings/validation, configurable monotonic flush, compact durable projection; unchanged diagnostics do not dirty flash. Pressure flush has a cooldown and uses dirty bytes, not total resident size. Preserve previous atomic files on failure.
- [x] Add core byte accounting, bounded admission and transient cleanup. Retain active grants/exclusions; expire unused error context/decisions/cooldowns. Do not disable sources on capacity. Checkpoint/restore and API paging must exceed 64 without truncation.
- [x] Add settings UI/Russian translations and capacity warning; keep bulk mutations bounded and scope checked. Page selection scans pages rather than trusting a truncated state.
- [x] Regression tests: >64 compact entries, daily/12h/unchanged/pressure checkpoint, corrupted storage, memory exhaustion preserves grants/denies, cleanup retains fresh evidence, reload, synthetic thousands-of-routes accounting/heap observation.
- [x] Run backend suite, frontend suite/type/lint/build, core race suites and compile check; inspect complete diff and document commands/limits. Review ARCHITECTURE/COMPONENTS, state, decisions, issues, pitfalls, roadmap and changelog.

Evidence: [storage report](../../AUTO_ROUTING_STORAGE.md). Seven race suites/clean apply and compile PASS; frontend 177/1697, backend97/97. No agents or commits. Ruling: public selection is page-scoped; bulk collects all filtered pages before confirmation, to avoid exceeding rpcd reply limits. Ruling: retained memory accounting is cached; in-flight counters update independently, so a healthy connection does not scan/serialize every pending record. Ruling: existing saved grants survive a smaller budget; growth then fails visibly.

Rulings: one finite verification job remains; no system drop_caches/periodic forced GC, no router/VPS access, no attribution of unrelated OOM to autorouting. Essential-data overflow rejects growth with a visible reason; saving alone does not free active route memory. Settings are not permission grants and never broaden routing scope.
