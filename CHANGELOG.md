# Changelog

All notable changes to Tripwire are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Transitive FFI pragma scan (Defense 2 Part 3): scoped audit driven by
  `staticExec` + POSIX `find | xargs grep -cE | awk`, anchored at the
  `{.` pragma delimiter. Direct scope defaults to `src` and is overridable
  via `TRIPWIRE_FFI_SCAN_PATHS`; transitive scope is opt-in via
  `TRIPWIRE_FFI_TRANSITIVE_PATHS` and the report prints an explicit
  "not scanned" line when unset rather than a silent zero. Detects
  `importc`, `importcpp`, `importobjc`, `importjs`. Gated by
  `-d:tripwireAuditFFI`. Replaces the v0 stub (857c7ef).
- `nearestMockHints`: Levenshtein-distance-1 "Did you mean:" suggestions
  appended to `UnmockedInteractionDefect` messages so a call that misses
  the mock queue by one typo names the closest registered mock (c8e279f).

### Fixed
- Chronos matrix cell: resolved ambiguous `Future` identifier in
  `src/tripwire/plugins/httpclient.nim` when both `std/asyncdispatch`
  and `chronos` are imported under `-d:chronos`. Three call sites
  qualified as `asyncdispatch.Future[AsyncResponse]` (2b759f2).

### Changed
- README: added alpha banner and scope/readiness preamble; tightened
  Defense 3 prose; author attribution set to
  `elijahr+tripwire@gmail.com` (2fc8614, 1161f57).

### Documentation
- Corrected `docs/design/v0.md` §11.2 Part 3: removed the
  `std/macros.walkPackedType` reference (that symbol is compiler-internal
  on Nim 2.2, not public) and documented the shipped `staticExec`-driven
  scan mechanism plus the v0.2 goal of eliminating env-var configuration
  in favour of automatic transitive discovery. Flagged shipped-vs-design
  discrepancies in module layout (`core/` subdirectory flattened,
  `cap_counter.nim` vs `compile_guards.nim`, `integration_unittest.nim`
  vs `integrations/unittest.nim`), DSL verb naming
  (`expectHttp`/`assertHttp`/`assertMock` vs plain `expect`/`assert`),
  and Defense 3 mechanism (`macro` with live counter check vs
  `template` with `when`).

## [0.1.0] - 2026-04-23

Initial public release. Project was developed under the working name
`nimfoot` (see rename commit 3f60ac2) and published as `tripwire`.

### Added
- **Core lifecycle** — `Verifier` ref type, thread-local verifier stack,
  `sandbox:` template, `verifyAll()` with three-guarantee checking order
  (unasserted interactions, unused mocks, pending async) (f40fcbc,
  cf36d19, 741df9f).
- **Base types** — `Plugin`, `Mock`, `MockResponse`, `Interaction`,
  `Timeline`; plugin base methods (`assertableFields`,
  `formatInteraction`, `matches`, `supportsPassthrough`,
  `passthroughFor`, `realize`) (2db4715, d34dc0d).
- **Defect hierarchy** — `TripwireDefect` root with FFI-scope footer on
  every message; `UnassertedInteractionsDefect`, `UnusedMocksDefect`,
  `UnmockedInteractionDefect`, `LeakedInteractionDefect`,
  `PostTestInteractionDefect`, `PendingAsyncDefect`,
  `UnmockableContainerDefect` (6145c31).
- **Plugin registry** — idempotent-by-name registration; per-plugin
  mock queues on the verifier (f1b0d99).
- **Context flags** — `AssertionContext`, `assertionsOpen`,
  `inAssertBlock`, `inAnyOrder` (27fcd2e).
- **`tripwireInterceptBody` combinator** — unified TRM body satisfying
  Defense 3 cap check, Defense 6 guard, timeline record, queue pop, and
  unmocked raise (55688ac).
- **Defense 3 (rewrite cap)** — compile-time counter with conservative
  threshold of 15, implemented as a `macro` that calls
  `std/macros.error` at expansion time (the original `template` +
  `when` + `static:` approach did not trip under Nim 2.2 due to
  sem-check ordering) (0a153d7).
- **Defense 1 (facade activation guard)** — `tripwire` facade emits a
  compile-time error when imported without `tripwireActive` defined;
  escape hatch via `-d:tripwireAllowInactive` (2bf5641).
- **Async helpers** — `Future` construction for `asyncdispatch`;
  chronos overlay gated by `when defined(chronos)` working around the
  chronos-`complete`-template composition issue from spike #6 (895ffa8,
  8ebef7f).
- **Config loader** — `tripwire.toml` discovery (walk up to first
  `.nimble` / `tripwire.toml`; honor `TRIPWIRE_CONFIG` env var); v0.2
  firewall keys parsed as no-op (d184a98).
- **MockPlugin** — generic value-typed arbitrary proc mocking;
  `MockUserResponse[T]` with `realize()` method; `mockable` + `expect`
  DSL; `assertMock` DSL (named to avoid colliding with the Nim
  builtin `assert` and with `unittest.expect`) (6a5530f, 28c8e2e,
  1e11304).
- **HttpClientPlugin** — sync and async `request` TRMs over
  `std/httpclient`; `Uri`-string overloads; wrapper canonicalization
  DSL covering `get`/`post`/`put`/`delete`/`patch`/`head` plus the
  matching `*Content` variants; `expectHttp`/`assertHttp` DSL macros
  (000c427, 09b7e7b, d6be08e).
- **OsProcPlugin** — `execProcess(seq)` and `execCmdEx` TRMs with fake
  `Process` scaffolding; `array[N, T]` variants 0..8; `openArray`
  fallback trap raising `UnmockableContainerDefect` (Defense 5)
  (0ed70f2, f63312b).
- **Integration** — `test:` template drop-in for `std/unittest`
  (default) and `unittest2` (via `-d:tripwireUnittest2`), with
  per-test verifier push/pop, `verifyAll()` in `try/finally`, and
  pending-async guard (630ab98, cc067e9).
- **`tripwire/auto` umbrella** — activation module imported via
  `--import:"tripwire/auto"` that registers every shipped plugin;
  no-op when `tripwireActive` is undefined (186f894).
- **Self-tests** — three-guarantees self-proof, Defense 3 and Defense 6
  regression suites, full compile-time + runtime matrix (eb45aac,
  a28f9ba, e6bd350).
- **Documentation** — `README.md` with SCOPE callout and alpha banner,
  `docs/quickstart.md`, `docs/plugin-authoring.md` enumerating the 13
  Plugin Authoring Rules, `docs/design/v0.md`, `spike/cap/REPORT.md`
  (4501c7a, c16a116, 375baac).

### Changed
- Renamed from `nimfoot` to `tripwire` across package manifest, source
  tree, test harness, documentation, and all identifiers (3f60ac2).

### Reference implementation
- Architectural concepts (three guarantees, Verifier/Timeline/Sandbox,
  plugin-authoring rules, loud-failure defects) are ported from
  `axiomantic/bigfoot` (pytest) and re-expressed in Nim 2.2.6 via
  term-rewriting macros.
