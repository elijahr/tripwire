# Tripwire v0.2 kickoff

## How to use this prompt

Paste into a fresh Claude Code / OpenCode session at `/Users/eek/Development/tripwire`. The session will invoke the `develop` skill and run Phase 0-4 for the v0.2 scope.

---

## Context

**Project:** Tripwire — Nim port of [bigfoot](https://github.com/axiomantic/bigfoot) (pytest test-mocking framework with three-guarantee enforcement: pre-authorized / asserted / consumed).

**Project root:** `/Users/eek/Development/tripwire`
**Branch:** `main` (trunk-based; v0 + v0.1 shipped)
**Tier:** COMPLEX

**Key artifacts:**
- Design doc: `docs/design/v0.md` (v0 canonical — has accurate-to-shipped banners where v0.1 pivoted)
- v0 impl plan: `~/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-tripwire-v0-impl.md` (historical; the spellbook path still uses the old `nimfoot` project-encoded prefix until the spellbook docs dir is renamed)
- v0 understanding doc: `~/.local/spellbook/docs/Users-eek-Development-nimfoot/understanding/understanding-tripwire-v0-2026-04-22.md`
- CHANGELOG: `CHANGELOG.md`
- README: `README.md` (alpha banner + SCOPE callout)

**v0 shipped:**
- Three-guarantee enforcement runtime (pre-authorized / asserted / consumed)
- Defenses 1, 3, 5, 6 (see design doc §10)
- Plugins: MockPlugin, HttpClientPlugin (sync + async + wrapper canonicalization), OsProcPlugin (seq + array[0..8] + openArray trap)
- Backends: std/unittest + unittest2
- MMs: refc + orc

**v0.1 shipped (post-v0 additions):**
- chronos matrix cell fix (`asyncdispatch.Future[T]` qualification in `plugins/httpclient.nim`)
- `nearestMockHints` — Levenshtein-distance-1 "Did you mean" suggestions on `UnmockedInteractionDefect`
- FFI audit (Defense 2 Part 3) — scoped `staticExec+find+grep` scanner via `TRIPWIRE_FFI_SCAN_PATHS` / `TRIPWIRE_FFI_TRANSITIVE_PATHS` env vars, gated by `-d:tripwireAuditFFI`

**Matrix state going into v0.2:** 601 OK across 5 cells (refc+sync, orc+sync, refc+unittest2, orc+unittest2, orc+chronos).

---

## v0.2 candidate items (pick scope in Phase 1.5 discovery)

Listed with rough effort + risk + value. Discovery should prioritize; not all of these need ship in v0.2.

### 1. `tripwireThread` wrapper — user-code `--threads:on` support (HIGH value, HIGH risk)

Spike #9 confirmed worker-thread TRMs hit the nil-verifier guard because thread-local verifier state doesn't inherit across thread boundaries. v0 documents threads as unsupported; v0.2 should add a `tripwireThread` template that wraps `spawn`/`createThread` with explicit verifier inheritance (copy the parent's verifier reference into the child thread-local slot before running the body).

Key risks:
- Nim's `threadvar` semantics and `ptr`-passing across threads
- Integration with `chronos.threadproc` (if used)
- Teardown ordering: parent's `verifyAll` must wait for child threads to finish before asserting consumed/asserted state

Acceptance: a user running `--threads:on` can call a `tripwireThread` wrapper and have the TRM interception fire in worker threads with interactions landing in the parent verifier's timeline.

### 2. `asyncCheck` patterns inside tests (MEDIUM value, MEDIUM risk)

v0 documents `asyncCheck` as unsupported inside sandbox bodies (because the spawned Future may outlive the test). v0.2 could support it via:
- A `asyncCheckInSandbox` helper that tracks spawned Futures and waits on them at `verifyAll` time
- OR explicit teardown hook that `.await` drains known-spawned Futures before checking `hasPendingOperations`

Acceptance: documented in quickstart; test shows `asyncCheck httpGet(...)` inside a sandbox resolving cleanly at teardown.

### 3. libc-level FFI firewall (HIGH value, VERY HIGH effort — probably defer to v0.3)

bigfoot's v3 layer — LD_PRELOAD shim that catches syscalls below the Nim runtime (the C layer: `open`, `connect`, `socket`, `fork`, etc.). Provides a safety net when plugins don't intercept everything.

Key risks:
- LD_PRELOAD is Linux-specific (macOS needs `DYLD_INSERT_LIBRARIES`; Windows is completely different)
- Requires writing C code and distributing a shim library
- Interaction with Nim's mechanism (does Nim go through libc or direct syscalls? Varies)

This is substantial — scoped out of v0.2 unless Phase 1.5 discovery proves a small viable subset.

### 4. Windows guard mode (MEDIUM value, HIGH effort)

Port the TRM injection + sandbox lifecycle to compile and run cleanly on Windows. v0 was developed on macOS/Linux; Windows compilation probably works (Nim is cross-platform) but the plugins (`osproc`, `httpclient`) need platform-specific verification.

Key risks:
- `osproc.execProcess` spawning semantics differ on Windows (`CreateProcess` vs `posix_spawn`)
- `addExitProc` behavior
- `chronos` on Windows (IOCP path)

Acceptance: CI runs tripwire's matrix on Windows; documented caveats in the SCOPE callout.

### 5. FFI audit — eliminate env-var configuration (MEDIUM value, MEDIUM-HIGH risk)

v0.1 FFI audit is scoped by user-supplied env vars. v0.2 goal: automatic transitive discovery. Options:
- `nim genDepend --project=<entry>` integration (two-stage build; ugly but works)
- Wait for a stable compiler-API enumeration of imports (uncertain timeline)
- Parse `.nimble`/`config.nims` to infer the user's source tree automatically

Acceptance: no env var required; transitive scope defaults to "everything your test binary imports".

### 6. Additional plugins (HIGH value, scattered effort)

Nominations:
- **`db_sqlite` / `db_postgres` / `db_mysql`** — intercept `exec`/`fastRows`/`getRow` etc.
- **`redis`** — intercept `redis.newRedis()`, `redis.sendCommand()`, etc.
- **cloud SDKs** — AWS SDK (if a Nim one exists); otherwise punt
- **`nativesockets` / `std/net`** — raw TCP/UDP interception

Each is a plugin authoring exercise following the 13 Rules in `docs/plugin-authoring.md`. Good practice for the plugin-authoring doc; discovery should check which ones have actual user demand vs are theoretical.

### 7. `balls` / `testament` integration (LOW-MEDIUM value, MEDIUM effort)

v0 ships integration with `std/unittest` and `unittest2`. Nim also has:
- `balls` — stream-oriented test runner, niche but well-liked
- `testament` — Nim compiler's own test suite runner; different model (per-file compile-fail expectations)

Integration would expand tripwire's reach but neither runner is as mainstream as unittest(2).

---

## Proposed v0.2 scope (for discovery to confirm or override)

**In scope (priority order):**
1. `tripwireThread` wrapper (#1) — highest user-value delta
2. `asyncCheck` inside sandbox (#2) — closes a documented gap
3. FFI audit transitive automation (#5) — removes a UX rough edge

**Deferred to v0.3+:**
- libc firewall, Windows guard, more plugins, balls/testament

Discovery should validate this ranking against user-demand signals, surface technical blockers, and adjust scope.

---

## Session preferences

- `autonomous_mode`: "autonomous"
- `parallelization`: "maximize"
- `worktree`: "none" (trunk-based, small team)
- `post_impl`: "offer_options"
- `dialectic_mode`: "none"
- `token_enforcement`: "gate_level"

---

## Invocation

```
/develop

Tripwire v0.2. See .claude/prompts/tripwire-v0.2-kickoff.md for full
context. Scope focus: tripwireThread, asyncCheck in sandbox, FFI audit
env-var elimination. Tier COMPLEX. Autonomous, maximize parallel,
no worktree.
```

Or just paste this file's contents into a fresh session and say "proceed."
