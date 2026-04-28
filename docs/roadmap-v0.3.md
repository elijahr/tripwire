# tripwire v0.3 roadmap

This file enumerates surfaces that v0.x deliberately does not ship and
sketches where they would land in v0.3. Each item names what v0
currently does (compile-time rejection, runtime rejection, or simple
absence) and what the v0.3 work would look like. Items marked
`[rationale TK]` are deferred pending an explicit design pass we have
not yet written.

This is a roadmap, not a wishlist: every entry exists because some v0
guard or absence will surface in user code (a `{.error.}`, a
`{.warning.}`, a runtime defect, or a missing plugin) and the user
deserves a single pointer for "where is this going?"

---

## 1. refc + threads support for `tripwireThread`

**Status (v0).** `tripwireThread` is compile-time rejected under
`--gc:refc --threads:on`. The empirical probe at
`spike/threads/v02_gc_safety_REPORT.md` showed refc's thread-local heap
silently drops child mutations to a shared `ref Verifier`, producing
false-green test outcomes. v0 emits an `{.error.}` at the
configuration rather than shipping a silently-broken path. The
negative-build probe lives at
`tests/threads/test_refc_threads_rejected.nim` (Cell 7's F2 guard in
`tripwire.nimble`).

**v0.3 target.** Two options, decision pending: (a) a POD-serialized
handoff (value-field `ThreadHandoff` with child-side thread-local copy
merged back at join time), preserving the invisible-at-callsite
property; or (b) explicit user documentation that `tripwireThread`
requires `arc`/`orc` and refc users should migrate. Option (a) is the
default direction.

---

## 2. Chronos `Future` registration via `asyncCheckInSandbox`

**Status (v0).** A chronos `Future[T]` passed to `asyncCheckInSandbox`
emits a compile-time `{.warning.}` and is NOT registered with the
sandbox's pending-async registry. v0's drain is
`std/asyncdispatch.poll`-only: chronos has a disjoint `FutureBase`
hierarchy and its own dispatcher, so no single drain call covers both.
The documented migration is to use chronos's native `waitFor` pattern
inside the sandbox body so the Future completes before the sandbox
closes.

**v0.3 target.** Native chronos drain integration. The design question
is whether to ship a parallel `chronosRegistry` with its own drain
call, or to type-erase both `FutureBase` hierarchies behind a single
`PendingAsyncOp` interface. The former is simpler but doubles teardown
ceremony; the latter is more uniform but requires careful
dispatcher-ownership reasoning. Cross-referenced with item 11
(chronos-on-worker-threads); they share the dispatcher-ownership
question and likely ship as one workstream.

---

## 3. Parameterized `withX(args) do: body` form

**Status (v0).** v0 ships the parameterless shape only:
`withTripwireThread do: body`, `withAsyncSandbox do: body`. The
parameterized form (template accepting user args that shape scoped
state, e.g. `withTimeBudget(ms) do: body` or `withMockProfile(p) do:
body`) is not exercised by any v0 surface and is therefore not
implemented.

**v0.3 target.** Wire the parameterized form in as new scoped-state
surfaces emerge. No speculative API; this entry exists so future
surface work follows existing `withX` conventions instead of
reinventing them.

---

## 4. Concurrent multi-spawn in `tripwireThread`

**Status (v0).** Sequential-only: `withTripwireThread do: body` blocks
until the child joins; the next spawn does not begin until the
previous has completed. The core obstacle is that N in-flight children
contend on the same `v.timeline` and `v.mockQueues` with no
single-join-barrier synchronization model, and v0's invariant "parent
does not mutate verifier while any child runs" has no obvious
generalization to N.

**v0.3 target.** A per-child timeline-merge design. The v0.3 design
must pin (a) the synchronization model for concurrent child-to-child
contention on `mockQueues`, (b) a merge-on-join algorithm for
per-child timelines, and (c) a failure mode for the
concurrent-mutation case (error, best-effort, or documented
non-determinism).

---

## 5. Structured code-driven configuration mechanism

**Status (v0).** v0 has no general code-driven configuration surface;
configuration is per-feature (defines, compile-time queries, the
`expect` DSL). The v0 alpha banner granted scope to remove
`TRIPWIRE_FFI_SCAN_PATHS` and `TRIPWIRE_FFI_TRANSITIVE_PATHS` without a
backward-compat shim; direct FFI scope is now auto-detected via
`std/compilesettings.querySetting(SingleValueSetting.projectPath)`,
and transitive scope is opt-in via `-d:tripwireAuditFFITransitive`.

**v0.3 target.** Introduce a structured code-driven config surface (a
compile-time `tripwireConfig` block, or a per-module `configureTripwire
do: body` template) consolidating existing compile-time knobs
(`-d:tripwireAuditFFI`, `-d:tripwireAuditFFITransitive`, prospective
`-d:tripwireInternalTypestate`) under one declarative surface. This is
ergonomic, not correctness; blocker-grade only once flag count becomes
unwieldy.

---

## 6. Plugin TRM auto-installation and ergonomic overlay

**Status (v0).** Plugin authors manually install TRM rules in their
plugin's init code; v0 ships authoring rules
(`docs/plugin-authoring.md`) that users follow by hand. The ergonomic
overlay defines `withX` and `name: body` conventions only for
framework-built surfaces; plugins do not get a derived ergonomic
surface automatically.

**v0.3 target.** Plugin TRM auto-installation: a declarative plugin
manifest (likely a macro over a typed record) that generates the TRM
installation boilerplate, emits an ergonomic overlay template
(`withMyPlugin do: body`), and verifies authoring rules at compile
time. Gated on enough user-written plugins to quantify the boilerplate
cost.

---

## 7. Typestate internal layer

**Status (v0).** Cut clean. v0 evaluated an optional internal-layer
typestate probe behind acceptance gates (compile green, tests green,
stripped binary size delta, user-surface invariance) and the spike did
not clear within budget. No `-d:tripwireInternalTypestate` flag ships
in v0; no typestate-refined `Verifier` variants exist in the codebase.
User-facing typestate is rejected entirely (it breaks the
"invisible-at-callsite" property); the internal-only probe was the
last venue.

**v0.3 target.** Re-run the internal-layer probe with an explicit
design that enumerates (a) which transition sites benefit from
compile-time refinement, (b) which state-agnostic readers must
continue to accept plain `Verifier` (notably `intercept.nim`'s
nil-verifier guard), and (c) a binary-size budget agreed in advance.
The probe stays off the v0.3 critical path; it ships only if gates
clear.

---

## 8. Async propagation through user-written helpers

**Status (v0).** `asyncCheckInSandbox(fut)` registers a `Future` passed
directly at the sandbox callsite. If a user-written helper calls
`asyncCheck` internally and returns, the pending `Future` is not
auto-propagated into the surrounding sandbox's registry: the helper
must be rewritten to return the `Future` (so the caller can pass it to
`asyncCheckInSandbox`) or take the registry as an argument.

**v0.3 target.** A TRM that rewrites plain `asyncCheck` calls inside a
sandbox scope to transparently register with the sandbox's registry,
making propagation through helpers invisible. The design risk is scope
creep: a naive TRM would rewrite every `asyncCheck` in the
compilation unit, including ones in test setup helpers that are
intentionally fire-and-forget. The v0.3 design must pin the scope
(lexical sandbox boundaries? dynamic via `currentVerifier()`?
compile-time context analysis?).

---

## 9. FFI audit scope expansion

**Status (v0).** FFI scanning covers two scopes: direct (compile-time
`projectPath`) and opt-in transitive (direct `requires` entries from
the project `.nimble`). Cross-module transitive pragma detection,
e.g. finding FFI pragmas in package X that were pulled in by package Y
which was a direct requirement, is NOT in v0. Walking the full search
path is rejected as unreadable (4,400 files, 8,200 hits in the probe).

**v0.3 target.** Two candidates, both deferred: (a) a per-direct-
requirement transitive walk that recursively resolves each required
package's own `.nimble` and aggregates at the package-root level
(adds 1-2 orders of magnitude in scanned files but output stays
per-package-grouped and actionable), or (b) a user-driven whitelist
(`-d:tripwireAuditFFIIncludePaths=pkgA,pkgB`) that keeps default scope
small and lets auditors opt into specific transitive paths. (b) is
cheaper.

---

## 10. Nested `tripwireThread` spawns

**Status (v0).** Rejected at runtime via
`NestedTripwireThreadDefect`. The hard question is which verifier a
nested child inherits (parent's, grandparent's, a freshly-spawned
child's) and how mock-queue state propagates across nesting levels.

**v0.3 target.** [rationale TK; requires a design pass that pins
verifier-inheritance semantics before implementation can start.]

---

## 11. Chronos-on-worker-threads composition

**Status (v0).** Rejected at runtime on child-thread entry via
`ChronosOnWorkerThreadDefect`. The guard calls
`hasPendingOperations()` before `pushVerifier`; a chronos dispatcher
with any pending operation in the child thread fails fast. Mixing
chronos's per-thread dispatcher with tripwire's per-thread verifier
produces two disjoint pending-operation models and no clean drain
point.

**v0.3 target.** A per-thread chronos dispatcher with explicit
cross-dispatcher Future handoff. Load-bearing for the v0.3 chronos
registration work (item 2): both items share the
dispatcher-ownership design question, and solving one likely unblocks
the other. Treat them as a single workstream.

---

## 12. Windows guard mode

**Status (v0).** Not implemented. The bigfoot/tripwire interception
path assumes POSIX signal and `LD_PRELOAD`-adjacent mechanisms that do
not port to Windows.

**v0.3 target.** [rationale TK; requires Windows-specific design
input not gathered yet.]

---

## 13. Libc-level FFI firewall

**Status (v0).** Not implemented. This is an out-of-process
`LD_PRELOAD` mechanism, conceptually separable from tripwire core; it
is a product-scope question (does tripwire ship the firewall, or
document integration with an external one?) rather than a design-gap
question.

**v0.3 target.** [rationale TK; product-scope decision pending.]

---

## 14. Additional stdlib and third-party plugins

**Status (v0).** v0 ships plugins for the currently-supported
surfaces only (`mock`, `httpclient`, `osproc`, `chronos_httpclient`,
`websock`). The framework supports plugin authoring
(`docs/plugin-authoring.md`); adding `db_sqlite`, `db_postgres`,
`db_mysql`, `redis`, `nativesockets`, and cloud SDK plugins is a
plugin-authoring exercise, not a framework change.

**v0.3 target.** Ship the high-demand plugins as the user base
signals them. Each new plugin becomes evidence for item 6 (plugin TRM
auto-installation), so a v0.3 decision on item 6 should precede a
push to author many plugins by hand.

---

## 15. `balls` / `testament` test framework integration

**Status (v0).** Not implemented. v0 integrates with `std/unittest`
(default) and `unittest2` (via `-d:tripwireUnittest2`).

**v0.3 target.** [rationale TK; deferred pending user demand
signal.]
