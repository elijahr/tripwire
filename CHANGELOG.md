# Changelog

All notable changes to Tripwire are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

In-development work past v0.0.1. NOT yet validated against any
real consumer project — the alpha banner still applies. Adds
worker-thread TRM interception, opt-in sandboxed-async spawn
registry, compile-time FFI audit auto-scope, and a named-sandbox
overload. Two breaking changes are queued for the next release,
both with compile-time guards and explicit migration recipes.

### Breaking

- **`tripwire/threads` requires `--gc:orc` or `--gc:arc`.** The new
  worker-thread module (`tripwireThread`, `withTripwireThread`,
  `runWithVerifier`) is rejected at compile time under
  `--gc:refc --threads:on`. Rationale: refc's thread-local heaps
  silently drop child-thread mutations to the shared `ref Verifier`,
  which breaks the "parent sees child interactions" invariant. The
  nimble matrix enforces this via a standalone negative-build probe
  (F2 guard, `gorgeEx`-driven, separate from the arc+threads positive
  cell #7). Non-threaded sandbox use under `--gc:refc` remains fully
  supported. refc+threads is a v0.3 investigation
  (see `spike/threads/v02_gc_safety_REPORT.md`).
- **FFI audit env vars removed.** `TRIPWIRE_FFI_SCAN_PATHS` and
  `TRIPWIRE_FFI_TRANSITIVE_PATHS` are gone. The scanner now
  auto-detects direct scope via
  `std/compilesettings.querySetting(SingleValueSetting.projectPath)`,
  and transitive scope is opt-in via `-d:tripwireAuditFFITransitive`
  (per-package aggregates for direct `.nimble` requires). Migration
  recipe below.

### Migration recipe

FFI-audit callers must drop the env-var form and move to compile
defines. `TRIPWIRE_CONFIG` (config-file locator) is unchanged.

```bash
# Direct scope — before (v0.1):
export TRIPWIRE_FFI_SCAN_PATHS="src"
nim c -r -d:tripwireAuditFFI mytest.nim

# Direct scope — after (v0.2):
nim c -r -d:tripwireAuditFFI mytest.nim

# Transitive scope — before (v0.1):
export TRIPWIRE_FFI_TRANSITIVE_PATHS="/usr/lib/nim"
nim c -r -d:tripwireAuditFFI mytest.nim

# Transitive scope — after (v0.2):
nim c -r -d:tripwireAuditFFI -d:tripwireAuditFFITransitive mytest.nim
```

For ad-hoc audits outside the default project scope, enable the
transitive scan toggle `-d:tripwireAuditFFITransitive`. The
`-d:tripwireAuditFFIExtraRequires:"pkg1,pkg2"` define adds extra
nimble packages to the transitive walk and is a no-op unless
`-d:tripwireAuditFFITransitive` is also set. See
`src/tripwire/audit_ffi.nim` for the scanner's scope rules.

### Added
- One-time stderr warning at config parse time when
  `[tripwire.firewall].guard = "..."` is encountered. The `guard` key
  was renamed to `default` in A4'''.5; pre-warning, stale
  `tripwire.toml` files using `guard = "warn"` silently reverted to
  `fmError` defaults with no operator signal. The warning prints once
  per `reloadConfig()` cycle. (`src/tripwire/config.nim`)
- CI-time enforcement test for plugin-name reserved-key collisions
  (`tests/test_firewall_reserved_keys.nim`). Asserts that no `Plugin`
  instance shadows the reserved `[tripwire.firewall]` sibling keys
  `default` or `allow`. A future plugin author who picks one of these
  names would silently misroute through the parser; the test catches
  it before merge.
- Pinned parsetoml version comment in `parseFirewallConfig`
  (`src/tripwire/config.nim`). Documents the `t.tableVal[]` API
  surface relied upon and the verified parsetoml version (0.7.2) so
  future bumps trigger re-verification.
- Case 13 (invalid mode in per-plugin entry raises `ValueError` at
  config load) is now part of the standing matrix in
  `tests/test_outside_sandbox_guard.nim` (was specified as optional in
  the original A4'''.5 implementation plan; now mandatory).
- **Chronos httpclient firewall-only plugin
  (`tripwire/plugins/chronos_httpclient`).** Auto-registers when
  `-d:chronos` is set. Enforces Guarantee #1 (every external call is
  pre-authorized) on chronos HTTP. Mocking is NOT supported on this
  surface — chronos's `HttpClientResponse.state` is private with no
  public constructor, so a synthetic-response plugin would require
  `cast` or `unsafeNew`. The firewall-only path sidesteps the wall
  entirely: the TRM body either raises `UnmockedInteractionDefect` or
  passes through to the real chronos proc; it never constructs a
  response. Consumers continue to mock HTTP responses via closure-based
  DI at their transport boundary (e.g. an `HttpSender` closure injected
  into a REST client) for G2/G3 coverage. Intercepts three surfaces:
  `send(req)` (the network boundary inside chronos's request
  lifecycle), `fetch(session, url)` (the URL-only convenience GET),
  and `fetch(request)` (the request-form convenience that returns
  `(status, body)`). The earlier assumption that the existing `send`
  TRM would transitively cover `fetch(req)` was wrong — chronos's
  `fetch(req)` body compiles outside the tripwire-active compilation
  unit, so the inner `request.send()` call inside chronos is NOT
  subject to TRM rewriting. An explicit `fetch(req)` TRM closes that
  G1 bypass; without it, `req.fetch()` reached the network with no
  firewall consultation.
  Standalone test cell `tests/test_chronos_httpclient_firewall.nim`
  (gated under `TRIPWIRE_TEST_CHRONOS=1`); standalone because the
  plugin's two TRMs plus the test wrappers would push the chronos
  aggregate over Defense 3's 15-rewrites-per-compilation-unit cap.
- **Firewall API: `sandbox.allow` / `sandbox.restrict` / `M(...)` /
  `firewallMode`.** The per-sandbox passthrough surface is renamed and
  expanded to match
  [axiomantic/bigfoot](https://github.com/axiomantic/bigfoot)'s
  vocabulary (the Python library tripwire ports). Pre-release: NO
  deprecation aliases — callers must move to the new names.
  - `sandbox.allow(plugin)` — blanket plugin-name shorthand. Any call
    routed through `plugin` falls through to the real implementation.
  - `sandbox.allow(plugin, predicate)` — closure escape hatch
    (`proc(procName, fingerprint: string): bool`).
  - `sandbox.allow(plugin, M(host = "*.example.com", httpMethod = "GET",
    path = ..., port = ..., scheme = ..., procName = ...))` — matcher
    DSL with glob wildcards (`*` zero-or-more, `?` exactly one).
    Plugins SHOULD honor structured fields when present; the default
    fingerprint-substring fallback works for any plugin out of the
    box.
  - `sandbox.restrict(plugin[, predicate|matcher])` — ceiling on
    `allow`. Bigfoot's mental model: `allow` lists what the sandbox
    PERMITS; `restrict` shrinks the permission set down to calls that
    fall inside the ceiling. A call passes iff some `allow` matches
    AND, if any `restrict` is configured for the plugin, some
    `restrict` matches too. `restrict` alone authorizes nothing — it
    filters the permission set, it does not grant. Most useful as a
    broad `allow(plugin)` narrowed by a `restrict(plugin, M(...))`.
  - `firewallMode: FirewallMode` on `Verifier` (default `fmError`,
    flippable to `fmWarn`). `fmWarn` mirrors bigfoot's `guard = "warn"`
    lane: emit a `tripwire firewall:` line to stderr and proceed via
    passthrough. Tripwire defaults to `fmError` (NOT bigfoot's `warn`)
    to preserve Guarantee 1; flip per-sandbox via `guard(v, fmWarn)`
    or project-wide via `[tripwire.firewall].default = "warn"` (with
    optional per-plugin `<plugin-name> = "warn"|"error"` overrides).
  - `firewallTest "name", [plugin1, plugin2], fmWarn: body` — sugared
    test wrapper that opens a sandbox, sets the mode, and blanket-
    allows each plugin in the list before running the body. Mirrors
    bigfoot's `@pytest.mark.allow(...)` per-test marker.
  - `[tripwire.firewall]` section in `tripwire.toml` honors `allow =
    ["plugin-name", ...]`, `default = "warn"|"error"` (project-wide
    outside-sandbox disposition), and per-plugin sibling keys
    (`<plugin-name> = "warn"|"error"`) that override `default` for
    individual plugins. Per-plugin name canonicalization is exact
    (sync `httpclient` and async `chronos_httpclient` are separate
    keys). Legacy flat-key `[firewall]` form is still parsed for
    backward compatibility. Replaces the prior allow-list/deny-all
    schema (which was parsed-but-unused; bigfoot's vocabulary was
    always the intent).
  - Plugin authors writing custom intercept combinators consume the
    decision via `firewallShouldRaise(v, plugin, procName,
    fingerprint)` (returns `bool`, side-effects the warn-side stderr
    line) or the lower-level `firewallDecideRaw` (pure, returns
    `FirewallDecision = fdAllow | fdWarn | fdRaise`).
  - Plugin-level base methods `supportsPassthrough` /
    `passthroughFor` moved from `tripwire/intercept` to
    `tripwire/plugin_base` so the firewall decision logic in
    `tripwire/sandbox` can call them without an import cycle. No call-
    site changes for plugin authors who already extended these.
- **`tripwire/threads`** — worker-thread TRM interception with
  parent-verifier inheritance. Canonical form `withTripwireThread do:
  body` pushes the parent `Verifier` onto the child thread's
  verifier stack via `runWithVerifier`. Low-level building blocks:
  `tripwireThread` (raw spawn wrapper), `ThreadHandoff` (heap-allocated
  parent-to-child handoff record), `childEntry` (rejection-check entry
  proc). Runtime rejections: `ChronosOnWorkerThreadDefect` if a
  chronos dispatcher has pending work on the child;
  `NestedTripwireThreadDefect` if `tripwireThread` fires from inside
  another `tripwireThread` block; `LeakedInteractionDefect` if there
  is no active parent verifier.
- **`tripwire/async_registry`** — opt-in sandboxed-async spawn
  registry. `asyncCheckInSandbox(fut)` registers a Future on the
  current verifier so leak detection is scoped to the sandbox (plain
  `asyncCheck` cross-contaminates across tests). `withAsyncSandbox do:
  body` wraps a sandbox with the registry attached. chronos Futures
  are rejected at compile time with a diagnostic (chronos registration
  deferred to v0.3).
- **`drainPendingAsync(v)`** in `tripwire/verify` — sync proc that
  loops `poll(timeout = 50)` until every registered Future has
  completed or `tripwireAsyncDrainTimeoutMs` elapses. Exposes
  per-Future spawn-site diagnostics when drain times out.
- **`-d:tripwireAsyncDrainTimeoutMs:N`** (intdefine) — drain-loop
  timeout in milliseconds. Default 5000.
- **`-d:tripwireAuditFFITransitive`** — opt-in transitive FFI scope
  with per-package aggregation from `.nimble` requires. Default-off.
- **`template sandbox*(name: static string, body: untyped)`** — named
  overload. The user-provided label propagates to `Verifier.name` and
  embeds in `UnassertedInteractionsDefect` / `UnusedMocksDefect`
  messages. Semantics otherwise identical to the unnamed form. Both
  overloads disambiguate cleanly: `sandbox: body` (unnamed),
  `sandbox "label": body` (named).
- **FFI audit scope** — direct scope now auto-detects from
  `querySetting(projectPath)`; transitive scope aggregates per
  `.nimble` package under the opt-in define above. Replaces the v0.1
  env-var contract.
- **New defect types:** `ChronosOnWorkerThreadDefect`,
  `NestedTripwireThreadDefect`. New `PendingAsyncDefect(msg, parent)`
  overload for drain-loop diagnostic paths (carries the underlying
  exception as `parent`).
- **Matrix cell #7 — arc+threads.** `tripwire.nimble` adds
  `--mm:arc --threads:on` cell exercising the new threads module.
  (arc rather than orc because Nim 2.2.6's orc cycle collector still
  has issues under `--threads:on`.)
- **Compile-time rejection of refc+threads** — nimble F2 guard
  asserts that `nim check --gc:refc --threads:on -d:tripwireActive`
  exits non-zero with the string
  `tripwireThread requires --gc:orc or --gc:arc` in stderr.

### Changed
- **`integration_unittest.test` teardown ordering.** The per-test
  template body now runs `drainPendingAsync(v)` (internal drain loop
  uses `poll(timeout = 50)`) → `hasPendingOperations()` (guard) →
  `poll(timeout = 0)` → `hasPendingOperations()` (gate) →
  `verifyAll()` at teardown. The guard before the final
  `poll(timeout = 0)` prevents `ValueError` on an empty dispatcher;
  the gate after is the user-visible `PendingAsyncDefect` raise site.
  Users who never call `asyncCheckInSandbox` see no behavioral change
  (the registry stays empty; drain is a no-op).

### Fixed
- `OutsideSandboxNoPassthroughDefect` message no longer recommends
  settings that re-raise the same defect. The pre-fix message
  suggested setting `[tripwire.firewall].<plugin>='warn'` or
  `[tripwire.firewall].default='warn'` for plugins that lack
  passthrough; both keep the plugin in `warn` mode where the
  no-passthrough defect raises. The corrected message points the
  operator at the two real fixes: install a sandbox to mock the call,
  or switch to `error` mode (per-plugin or default) to raise the
  standard `LeakedInteractionDefect` instead. (`src/tripwire/errors.nim`)

### Deferred to v0.3
- **Env-var replacements.** `TRIPWIRE_FFI_SCAN_PATHS` and
  `TRIPWIRE_FFI_TRANSITIVE_PATHS` remain removed; richer override
  hooks (if any) will land alongside the libc-level firewall work.
- **chronos Future registration.** `asyncCheckInSandbox` currently
  emits a compile-time warning for chronos Futures and accepts only
  `std/asyncdispatch.Future[T]`. Full chronos registration is
  deferred.
- **Parameterized `withX(args) do: body` form.** Both
  `withTripwireThread` and `withAsyncSandbox` ship as bare-body
  forms only; no user-threaded argument surface yet.
- **Typestate internal layer.** v0.2 does not land the
  `-d:tripwireInternalTypestate` instrumentation; the probe is
  carried to v0.3. See `docs/roadmap-v0.3.md`.

## [0.0.1] - 2026-04-23

Initial release. Tripwire is the Nim port of
[bigfoot](https://github.com/axiomantic/bigfoot). Project was developed
under the working name `nimfoot` (see rename commit 3f60ac2) and
published as `tripwire`.

### Added
- **Three-guarantee model** — `sandbox:` template and `verifyAll()`
  enforce that every external call is pre-authorized, every recorded
  interaction is explicitly asserted, and every registered mock is
  consumed; violations raise non-catchable `TripwireDefect`s in a
  fixed checking order (unasserted interactions, unused mocks, pending
  async) (f40fcbc, cf36d19, 741df9f).
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
- **`nearestMockHints`** — Levenshtein-distance-1 "Did you mean:"
  suggestions appended to `UnmockedInteractionDefect` messages so a
  call that misses the mock queue by one typo names the closest
  registered mock (c8e279f).
- **Transitive FFI pragma scan (Defense 2 Part 3)** — scoped audit
  driven by `staticExec` + POSIX `find | xargs grep -cE | awk`,
  anchored at the `{.` pragma delimiter. Direct scope defaults to
  `src` and is overridable via `TRIPWIRE_FFI_SCAN_PATHS`; transitive
  scope is opt-in via `TRIPWIRE_FFI_TRANSITIVE_PATHS` and the report
  prints an explicit "not scanned" line when unset rather than a
  silent zero. Detects `importc`, `importcpp`, `importobjc`,
  `importjs`. Gated by `-d:tripwireAuditFFI`. Replaces the v0 stub
  (857c7ef).
- **Core lifecycle** — `Verifier` ref type, thread-local verifier
  stack, `sandbox:` template, `verifyAll()` with three-guarantee
  checking order (f40fcbc, cf36d19, 741df9f).
- **Base types** — `Plugin`, `Mock`, `MockResponse`, `Interaction`,
  `Timeline`; plugin base methods (`assertableFields`,
  `formatInteraction`, `matches`, `supportsPassthrough`,
  `passthroughFor`, `realize`) (2db4715, d34dc0d).
- **Defect hierarchy** — `TripwireDefect` root with FFI-scope footer
  on every message; `UnassertedInteractionsDefect`,
  `UnusedMocksDefect`, `UnmockedInteractionDefect`,
  `LeakedInteractionDefect`, `PostTestInteractionDefect`,
  `PendingAsyncDefect`, `UnmockableContainerDefect` (6145c31).
- **Plugin registry** — idempotent-by-name registration; per-plugin
  mock queues on the verifier (f1b0d99).
- **Context flags** — `AssertionContext`, `assertionsOpen`,
  `inAssertBlock`, `inAnyOrder` (27fcd2e).
- **`tripwireInterceptBody` combinator** — unified TRM body
  satisfying Defense 3 cap check, Defense 6 guard, timeline record,
  queue pop, and unmocked raise (55688ac).
- **Defense 3 (rewrite cap)** — compile-time counter with
  conservative threshold of 15, implemented as a `macro` that calls
  `std/macros.error` at expansion time (the original `template` +
  `when` + `static:` approach did not trip under Nim 2.2 due to
  sem-check ordering) (0a153d7).
- **Defense 1 (facade activation guard)** — `tripwire` facade emits a
  compile-time error when imported without `tripwireActive` defined;
  escape hatch via `-d:tripwireAllowInactive` (2bf5641).
- **Async helpers** — `Future` construction for `asyncdispatch`;
  chronos overlay gated by `when defined(chronos)` working around the
  chronos-`complete`-template composition issue from spike #6
  (895ffa8, 8ebef7f).
- **Config loader** — `tripwire.toml` discovery (walk up to first
  `.nimble` / `tripwire.toml`; honor `TRIPWIRE_CONFIG` env var); v0.2
  firewall keys parsed as no-op (d184a98).
- **Self-tests** — three-guarantees self-proof, Defense 3 and Defense
  6 regression suites, full compile-time + runtime matrix (eb45aac,
  a28f9ba, e6bd350).
- **Documentation** — `README.md` with SCOPE callout and alpha
  banner, `docs/quickstart.md`, `docs/plugin-authoring.md` enumerating
  the 13 Plugin Authoring Rules, `docs/design/v0.md`,
  `spike/cap/REPORT.md` (4501c7a, c16a116, 375baac).

### Changed
- Renamed from `nimfoot` to `tripwire` across package manifest, source
  tree, test harness, documentation, and all identifiers (3f60ac2).
- README: added alpha banner and scope/readiness preamble; tightened
  Defense 3 prose; author attribution set to
  `elijahr+tripwire@gmail.com` (2fc8614, 1161f57).

### Fixed
- Chronos matrix cell: resolved ambiguous `Future` identifier in
  `src/tripwire/plugins/httpclient.nim` when both `std/asyncdispatch`
  and `chronos` are imported under `-d:chronos`. Three call sites
  qualified as `asyncdispatch.Future[AsyncResponse]` (2b759f2).

### Documentation
- Corrected `docs/design/v0.md` §11.2 Part 3: removed the
  `std/macros.walkPackedType` reference (that symbol is
  compiler-internal on Nim 2.2, not public) and documented the
  shipped `staticExec`-driven scan mechanism plus the v0.2 goal of
  eliminating env-var configuration in favour of automatic transitive
  discovery. Flagged shipped-vs-design discrepancies in module layout
  (`core/` subdirectory flattened, `cap_counter.nim` vs
  `compile_guards.nim`, `integration_unittest.nim` vs
  `integrations/unittest.nim`), DSL verb naming
  (`expectHttp`/`assertHttp`/`assertMock` vs plain `expect`/`assert`),
  and Defense 3 mechanism (`macro` with live counter check vs
  `template` with `when`).

### Reference implementation
- Architectural concepts (three guarantees, Verifier/Timeline/Sandbox,
  plugin-authoring rules, loud-failure defects) are ported from
  [axiomantic/bigfoot](https://github.com/axiomantic/bigfoot) (pytest)
  and re-expressed in Nim 2.2.6 via term-rewriting macros.
