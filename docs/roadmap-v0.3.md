# Tripwire v0.3 roadmap

This document enumerates the surfaces that v0.2 intentionally left closed and
maps each to the v0.2 constraint that motivates the v0.3 work. Items below are
anchored to the v0.2 design doc **§11 (Non-goals, explicitly out of scope)** and
§12 (Open questions, some closed). Each entry is a concrete follow-up, not a
wishlist — if an item lacks a shippable rationale it is marked with a placeholder.

> Scope note: this file is an early-authored roadmap (per impl plan Task 5.6).
> It freezes the deferral surface at v0.2 cut time so users who hit a `{.error.}`
> or `{.warning.}` guard have a single pointer to the v0.3 design workstream.
>
> Citation note: section references labeled "v0.2 design doc §N" (e.g.
> §8 GC-safety, §11 Non-goals, §12 Open questions, §13 Rejected alternatives)
> point to the v0.2 design planning artifact at
> `~/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-design.md`,
> not to the in-repo `docs/design/v0.md` (which is the v0 design and uses a
> different section numbering). The v0.2 design artifact was not shipped
> in-tree; an in-repo v0.2 design doc is itself a v0.3 roadmap item
> (see §16 below).

---

## Task 5.3 typestate spike — decision

The v0.2 impl plan gated an optional internal-layer typestate probe
(§7.2, Task 5.3) behind four acceptance gates (compile green, tests green,
stripped binary size delta, user-surface invariance). At v0.2 cut the spike
was **cut clean**: no `-d:tripwireInternalTypestate` flag ships in v0.2,
and no typestate-refined `Verifier` variants landed. Rationale recorded at
design §13.10: user-facing typestate is rejected entirely (breaks
"invisible-at-callsite"); the internal-only probe was the last probe venue,
and it did not clear its gates within the 30-minute time budget documented
at impl plan §5.3 / §WI5 rollback signal.

**v0.3 target.** Re-run the internal-layer probe with an explicit design
document that enumerates (a) which transition sites benefit from
compile-time refinement, (b) which state-agnostic readers MUST continue
to accept plain `Verifier` (per design §7.3's caveat about
`intercept.nim`'s nil-verifier guard), and (c) a binary-size budget agreed
in advance. The probe remains off the v0.3 critical path; it ships only
if gates clear.

---

## 1. refc + threads support for `tripwireThread`

**Status (v0.2).** `tripwireThread` is compile-time rejected under
`--gc:refc --threads:on`. Empirical probe evidence (design §8;
`spike/threads/v02_gc_safety.nim`) showed refc's thread-local heap silently
drops child mutations to a shared `ref Verifier`, producing a false-green
test outcome. v0.2 emits a `{.error.}` at the refc+threads configuration
rather than shipping a silently-broken path.

**v0.3 target.** Two options, decision deferred to v0.3 design:
(a) a POD-serialized handoff mirroring spike #9's Q4 technique
(value-field `ThreadHandoff`, child-side thread-local copy merged back
at join time), or (b) explicit user documentation that `tripwireThread`
requires orc/arc and that refc users should migrate their gc mode.
Option (a) preserves the invisible-at-callsite property; option (b) is
strictly cheaper but leaves a configuration hole. Design §11's disposition
column flags (a) as the default direction.

---

## 2. Chronos Future registration via `asyncCheckInSandbox`

**Status (v0.2).** Chronos `Future[T]` passed to `asyncCheckInSandbox` emits
a compile-time `{.warning.}` (design §4.1) and is NOT registered with the
sandbox's pending-async registry. v0.2's registry drain is
`std/asyncdispatch.poll`-only: chronos has a disjoint `FutureBase` hierarchy
and its own dispatcher, so no single drain call covers both. The documented
migration is to use chronos's native `waitFor` pattern inside the sandbox
body so the Future completes before the sandbox closes.

**v0.3 target.** Native chronos drain integration. The design question is
whether to ship a second registry (`chronosRegistry` parallel to the
asyncdispatch one) with its own drain call, or to type-erase both
`FutureBase` hierarchies behind a `PendingAsyncOp` interface. The former
is simpler but doubles the teardown ceremony; the latter is more uniform
but requires careful dispatcher-ownership reasoning. Cross-references:
design §4.1, §11 "chronos Futures with asyncCheckInSandbox",
§13.11 (rejected: best-effort chronos-on-worker-threads).

---

## 3. Parameterized `withX(args) do: body` form

**Status (v0.2).** Design §6.1 Rule A specifies `withX(args) do: body` for
templates that pass implicit state. v0.2 ships the parameterless shape
(`withTripwireThread do: body`, `withAsyncSandbox do: body`). The
parameterized form — where the template accepts user arguments that shape
the scoped state — is not exercised by any v0.2 surface and is therefore
not implemented.

**v0.3 target.** Wire the parameterized form into the ergonomic overlay
naturally as new scoped-state surfaces emerge (e.g., a `withTimeBudget(ms)
do: body` scoped clock, or a `withMockProfile(profile) do: body` scoped
mock-profile swap). No speculative API is added here; this entry captures
the design-vs-implementation gap so future surface work references §6.1
Rule A instead of reinventing conventions.

---

## 4. Concurrent multi-spawn in `tripwireThread`

**Status (v0.2).** Sequential-only: `withTripwireThread do: body` blocks
until the child joins; the next spawn does not begin until the previous
has completed. Design §11 flags concurrent multi-spawn as the hardest
deferred item. The core obstacle (design §4, §3.4) is that N in-flight
children contend on the same `v.timeline` and `v.mockQueues` with no
single-join-barrier synchronization model, and the v0.2 invariant
"parent does not mutate verifier while any child runs" has no obvious
generalization to N.

**v0.3 target.** A per-child timeline-merge design. Spike #9 retains the
`Atomic[int]` completion counter (design §4 note at line 383) for this
workstream. The v0.3 design doc must pin (a) the synchronization model
for concurrent child-to-child contention on `mockQueues`, (b) a
merge-on-join algorithm for per-child timelines, and (c) a failure mode
for the concurrent-mutation case — error, best-effort, or documented
non-determinism.

---

## 5. Env-var config replacement with a structured code-driven mechanism

**Status (v0.2).** v0.2 removes `TRIPWIRE_FFI_SCAN_PATHS` and
`TRIPWIRE_FFI_TRANSITIVE_PATHS` (design §5.5, §11 "Backward-compat shim
for removed env vars"). Direct FFI scope is auto-detected via
`std/compilesettings.querySetting(SingleValueSetting.projectPath)`;
transitive scope is an opt-in `-d:tripwireAuditFFITransitive` that parses
the project `.nimble`. The alpha banner grants scope for the break; no
shim ships. The design-level concern is that tripwire has no general
code-driven configuration mechanism — configuration is per-feature
(defines, compile-time queries, `expect` DSL).

**v0.3 target.** Introduce a structured code-driven config surface (a
compile-time `tripwireConfig` block, or a per-module `configureTripwire
do: body` template) that replaces ad-hoc defines as the feature count
grows. Scope: consolidate the existing compile-time knobs
(`-d:tripwireAuditFFI`, `-d:tripwireAuditFFITransitive`, prospective
`-d:tripwireInternalTypestate`) under one declarative surface. This is
ergonomic, not correctness — blocker-grade only once the flag count
becomes unwieldy.

---

## 6. Plugin TRM auto-installation and ergonomic overlay parameterized forms

**Status (v0.2).** Plugin authors manually install their TRM rules in
their plugin's init code; v0.2 ships 13 authoring rules
(`docs/plugin-authoring.md`) that users follow by hand. The ergonomic
overlay (§6) defines `withX` and `name: body` conventions but only for
framework-built surfaces; plugins do not get a derived ergonomic surface
automatically.

**v0.3 target.** Plugin TRM auto-installation — a declarative plugin
manifest (likely a macro over a typed record) that generates the TRM
installation boilerplate, emits an ergonomic overlay template
(`withMyPlugin do: body`) conforming to §6.1, and verifies the 13
authoring rules at compile time. Gates completion once enough
user-written plugins exist to quantify the boilerplate cost; design §11
"Additional plugins" tracks the demand signal.

---

## 7. Typestate internal layer (conditional; see Task 5.3 decision above)

**Status (v0.2).** Cut clean. See "Task 5.3 typestate spike — decision"
above. No `-d:tripwireInternalTypestate` surface ships in v0.2; no
typestate-refined `Verifier[State]` variants exist in the codebase.

**v0.3 target.** See Task 5.3 decision section. If the re-probe clears
its gates, ship behind the internal define with explicit documentation
of which transition sites are refined; if it doesn't clear, document
the closed gate here and mark the typestate workstream as permanently
deferred (design §13.10 already records that user-facing typestate is
rejected entirely, not deferred).

---

## 8. Async propagation through user-written helpers

**Status (v0.2).** `asyncCheckInSandbox(fut)` registers a Future passed
directly at the sandbox callsite. If a user-written helper calls
`asyncCheck` internally and returns, there is no automatic propagation
of the pending Future into the surrounding sandbox's registry — the
helper must be rewritten to return the Future (so the caller can pass it
to `asyncCheckInSandbox`) or to take the registry as an argument. Design
§11 "Plain `asyncCheck` correctness" documents this as a limitation and
suggests a TRM on `system.asyncCheck` as a v0.3 candidate.

**v0.3 target.** A TRM that rewrites plain `asyncCheck` calls inside a
sandbox scope to transparently register with the sandbox's registry,
making propagation through helpers invisible. The design risk is scope
creep — a naive TRM would register every `asyncCheck` in the compilation
unit, including ones in test setup helpers that are intentionally
fire-and-forget. The v0.3 design must pin the scope (lexical sandbox
boundaries? dynamic via `currentVerifier()`? compile-time context
analysis?).

---

## 9. FFI audit scope expansion

**Status (v0.2).** FFI scanning covers two scopes: direct (compile-time
`projectPath`) and opt-in transitive (direct `requires` entries from the
project `.nimble`). Cross-module transitive pragma detection — e.g.,
finding FFI pragmas in package X that were pulled in by package Y which
was a direct requirement — is NOT in v0.2. Design §5.3 / §5.4 quantifies
why walking the full search path is rejected (4,400 files, 8,200 hits,
unreadable output).

**v0.3 target.** Two candidates, both deferred: (a) a per-direct-
requirement transitive walk that recursively resolves each required
package's own `.nimble` and aggregates at the package-root level (adds
1-2 orders of magnitude in scanned files, but output is still
per-package-grouped and therefore actionable), or (b) a user-driven
whitelist (`-d:tripwireAuditFFIIncludePaths=pkgA,pkgB`) that keeps
direct+opt-in default scope small and lets auditors opt into specific
transitive paths. Decision deferred to v0.3 design; (b) is cheaper.

---

## 10. Nested `tripwireThread` spawns

**Status (v0.2).** Rejected at runtime via `NestedTripwireThreadDefect`.
Design §11 marks this as "v0.3 or later — would require ref-counted
child verifier chains; semantics unclear." The hard question is which
verifier a nested child inherits (parent's, grandparent's, a
freshly-spawned child's) and how mock-queue state propagates across
nesting levels.

**v0.3 target.** [rationale TK — requires v0.3 design doc pinning
verifier-inheritance semantics before implementation can start. See
v0.2 design §11 (non-goal row "nested `tripwireThread`") and §8.]

---

## 11. Chronos-on-worker-threads composition

**Status (v0.2).** Rejected at runtime on child-thread entry via
`ChronosOnWorkerThreadDefect`. The guard calls `hasPendingOperations()`
before `pushVerifier`; a chronos dispatcher with any pending operation
in the child thread fails fast. Rationale (design §3.6): mixing chronos's
per-thread dispatcher with tripwire's per-thread verifier produces two
disjoint pending-operation models and no clean drain point.

**v0.3 target.** A per-thread chronos dispatcher with explicit
cross-dispatcher Future handoff. This is load-bearing for the v0.3
chronos registration work (item 2 above) — both items share the
dispatcher-ownership design question, and solving one likely unblocks
the other. Design §11 flags this as the same v0.3 milestone as item 2;
the v0.3 impl plan should consider them as a single workstream.

---

## 12. Windows guard mode

**Status (v0.2).** Not implemented. Design §11 flags as "Windows-specific
interception mechanism; not tackled in v0.2." The bigfoot/tripwire
interception path assumes POSIX signal and LD_PRELOAD-adjacent
mechanisms that do not port to Windows.

**v0.3 target.** [rationale TK — requires Windows-specific design input
that v0.2 explicitly did not gather. See v0.2 design §11.]

---

## 13. Libc-level FFI firewall (bigfoot v3 analogue)

**Status (v0.2).** Not implemented. Design §11 notes this as
"out-of-process LD_PRELOAD mechanism; separable from tripwire core."
It is a product-scope question (does tripwire ship the firewall, or
document integration with an external one?) rather than a design-gap
question.

**v0.3 target.** [rationale TK — product-scope decision pending. See
v0.2 design §11 and bigfoot v3 design materials.]

---

## 14. Additional stdlib and third-party plugins

**Status (v0.2).** v0.2 ships plugins for the currently-supported
surfaces only. The framework supports plugin authoring (13 rules
documented in `docs/plugin-authoring.md`); adding `db_sqlite`,
`db_postgres`, `db_mysql`, `redis`, `nativesockets`, and cloud SDK
plugins is purely an authoring exercise. Design §11 flags these as
"plugin-authoring exercise; framework supports them already."

**v0.3 target.** Ship the high-demand plugins as the user base signals
them. Gated on demand, not on technical work. Design note: each new
plugin becomes evidence for item 6 above (plugin TRM auto-installation),
so the v0.3 decision on item 6 should precede a push to author many
plugins by hand.

---

## 15. Balls / testament integration

**Status (v0.2).** Not implemented. Design §11 flags as "deferred pending
user demand." v0.2 integrates with `std/unittest` only.

**v0.3 target.** [rationale TK — deferred pending user demand signal.
See v0.2 design §11.]

---

## 16. Ship a v0.2 design doc in the repo tree

**Status (v0.2).** The v0.2 design work lives only as a planning artifact
at `~/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-design.md`.
The in-repo `docs/design/v0.md` is the v0 doc and does not reflect the
v0.2 thread-safety amendment, async registry, or FFI auto-discovery.
Roadmap entries above reference the planning artifact by its section
numbering; readers following the "§11" / "§12" / "§13" citations who
only have the repo in front of them will not find those sections.

**v0.3 target.** Ship `docs/design/v0.2.md` (or fold v0.2 amendments
into `docs/design/v0.md` with a clear v0-vs-v0.2 section delineation).
Until then, roadmap citations remain anchored to the out-of-repo planning
artifact (see preamble citation note).

---

## Cross-references

- v0.2 design doc §11 (Non-goals): authoritative source for the deferral table.
- v0.2 design doc §12 (Open questions): some items closed at v0.2 cut
  (GC-safety spike, chronos detection mechanism); some remain live for v0.3
  planning (test-file layout, release cadence for typestate).
- v0.2 design doc §13 (Rejected alternatives): documents what was evaluated
  and rejected entirely (e.g., §13.10 user-facing typestate, §13.11
  best-effort chronos-on-worker-threads).
- `CHANGELOG.md`: the v0.2 "Deferred to v0.3" section links back here.
