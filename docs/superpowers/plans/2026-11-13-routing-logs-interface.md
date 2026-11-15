# Routing, logs and interface implementation plan

**Goal:** implement the six requested improvements without publishing or accessing live devices.

**Architecture:** resolve real destination addresses before user route rules, retaining rule order. Keep a bounded 24-hour application journal independent of the system log ring. Use existing LuCI controls and domain syntax.

**Tech stack:** TypeScript/LuCI, ucode, sing-box.

**Spec:** user request and subsequent clarification in this session: bare domains include subdomains; `full:` matches exactly; resolution applies to every routing action.

## Constraints

Preserve existing uncommitted changes. No live devices, deployments or commits. Existing static hosts and service exclusions retain priority. Journal storage uses RAM-backed temporary storage; size limits override age retention.

## Tasks

- [x] Resolve: add disabled/all/selected settings, reuse domain syntax, validate server-side, generate resolve before user rules. Test mode defaults, invalid/empty selected lists, exact/suffix matching, static hosts and route order.
- [x] Journal: retain captured records for 86400 seconds with a 2 MiB total archive limit, oldest first eviction, collection every 1.5s while the UI is closed, temporary archive across state-service restarts, authenticated clear RPC. Test expiry, capacity, clear/deduplication, reload and UI failures.
- [x] Interface: remove theme collision from fallback heading and decorative primary badge; contain configuration button contents; show explicit manual update-check feedback. Run focused frontend regressions.
- [x] Local verification: run relevant backend and frontend checks, lint/build, inspect resulting changes, update only affected product documentation.

## Review focus

Resolution must not return Fake-IP, reorder rules or override manual hosts. Clearing must not re-import the system ring. Journal expiry must invalidate browser caches. Failed clear must leave displayed logs intact. Long translated labels must remain inside their buttons.
