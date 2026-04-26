# tripwire

Test mocking framework for Nim, enforcing the **three guarantees**:

1. Every external call is pre-authorized.
2. Every recorded interaction is explicitly asserted.
3. Every registered mock is consumed.

Violations raise `{.TripwireDefect.}`s that are NOT catchable by user
code — they abort the test binary with a stack trace that names the
offending interaction.

Nim adaptation of [bigfoot](https://github.com/axiomantic/bigfoot) (pytest).
Bigfoot is the canonical UX reference for tripwire's API; the firewall
vocabulary (`allow` / `restrict` / matchers / `guard = "warn"|"error"`)
is taken directly from bigfoot.

> **ALPHA** — tripwire is pre-1.0 and has NOT been validated against
> any real consumer project. Breaking changes may ship in any
> pre-1.0 release. Each release's CHANGELOG includes explicit
> migration steps. The next release will remove the
> `TRIPWIRE_FFI_*` environment variables (config becomes
> compile-define only) and the new `tripwire/threads` module will
> require `--gc:orc` or `--gc:arc` (refc rejected at compile time);
> see [`CHANGELOG.md`](CHANGELOG.md) for the queued migration
> recipe.

## Unreleased capabilities

The following capabilities are merged on `main` but NOT in any
published release. The version on disk is still `0.0.1`; consumers
who pull from `main` get them, consumers who `nimble install`
do not.

- `tripwireThread` / `withTripwireThread` — verifier-inheriting thread
  primitives so child threads see the parent sandbox's mock queue and
  timeline (design §3).
- `asyncCheckInSandbox` — opt-in `asyncdispatch` Future registration;
  `drainPendingAsync` on sandbox teardown raises `PendingAsyncDefect`
  for any Future still in flight (design §4).
- Scoped FFI auto-discovery — real `{.importc.}` / `{.importcpp.}` /
  `{.importobjc.}` / `{.importjs.}` pragma scanner replacing the
  env-var-driven v0.0.1 stub (Defense 2 Part 3, design §5).
- Named sandbox overload — `sandbox "label": body` surfaces the label
  in defect messages for faster triage (design §6.3).

See [`CHANGELOG.md`](CHANGELOG.md) for the full migration recipe.

## !! SCOPE

**tripwire intercepts Nim source calls only.** FFI (`{.importc.}`,
`{.dynlib.}`, `{.header.}`) is NOT intercepted. This is an
intentional scope cut: the libc-level firewall (bigfoot's v3 layer)
is a future-release item.

An opt-in FFI *audit* ships via `-d:tripwireAuditFFI`. When set,
tripwire auto-scopes to the project path (via Nim's
`std/compilesettings.querySetting(projectPath)`) at compile time and
emits a `{.hint.}` listing every `{.importc.}`, `{.importcpp.}`,
`{.importobjc.}`, and `{.importjs.}` pragma it finds, with per-file
counts and a grand total. Unreleased work on `main` replaced the
v0.0.1 `TRIPWIRE_FFI_SCAN_PATHS` / `TRIPWIRE_FFI_TRANSITIVE_PATHS`
env vars with compile-time auto-discovery (Defense 2 Part 3, design
§5). To extend the scan beyond the project to nimble-managed
dependencies, set `-d:tripwireAuditFFITransitive` (which walks the
nimble deps tree); the
`-d:tripwireAuditFFIExtraRequires="pkg1,pkg2"` escape hatch adds
extra package names to that walk and is a no-op unless
`-d:tripwireAuditFFITransitive` is also set.
See [`CHANGELOG.md`](CHANGELOG.md) for the queued migration recipe.

Every defect message includes an FFI-scope footer pointing at
`docs/concepts.md#scope`; if your test reports `UnmockedInteraction`
for a call you thought was mocked, re-check whether it crosses the
Nim/FFI boundary.

## Status: 0.0.1 (unreleased work on main)

- Published nimble version is `0.0.1`. Tracks A–H landed in v0.0.1;
  WI1-WI5 (worker-thread interception, async registry, FFI
  auto-discovery, named sandbox, release polish) are merged on
  `main` and queued for the next release. NO real consumer
  validation has been performed yet; the alpha banner stands.
- Matrix green across 7 cells: refc + orc × sync + unittest2 (cells
  1-4), standalone `test_osproc_arrays` under orc (cell 5),
  orc+chronos opt-in (cell 6), arc+threads (cell 7), plus a
  separate negative refc+threads build probe (F2 guard). This
  matrix proves tripwire's internal contract; it does NOT prove a
  third-party consumer project can integrate tripwire end-to-end.
- chronos cell opt-in (`TRIPWIRE_TEST_CHRONOS=1 nimble test`);
  requires the chronos package in the consumer's `nimble requires`.

See [`docs/quickstart.md`](docs/quickstart.md) for the full walkthrough.

## Install

```bash
nimble install tripwire
```

## Minimal example

```nim
import tripwire
import tripwire/plugins/httpclient as nfhttp
import std/[httpclient, options, tables]

test "user fetch":
  sandbox:
    let c = newHttpClient()
    nfhttp.expectHttp get(c, "http://api/u/1"):
      respond:
        status: 200
        body: """{"id":1}"""
    let r = c.get("http://api/u/1")
    check r.body.contains("\"id\":1")
    nfhttp.assertHttp get(c, "http://api/u/1"):
      responded:
        status: 200
```

## Firewall mode

Tripwire's three guarantees are strict by default — every unmocked call
raises a defect. For the rare legitimate spy-mode case (the test wants
the real implementation to run, just inside the sandbox), use the
firewall API. Vocabulary is taken from
[axiomantic/bigfoot](https://github.com/axiomantic/bigfoot).

### `allow` — selectively permit real calls

```nim
sandbox:
  # Plugin-name shorthand: ANY call routed through dnsPlugin passes.
  allow(dnsPlugin)

  # Matcher DSL: only requests to *.example.com pass.
  allow(httpclientPlugin, M(host = "*.example.com"))

  # Closure escape hatch: any predicate over (procName, fingerprint).
  allow(socketPlugin, proc(p, fp: string): bool =
    fp.contains("127.0.0.1"))
```

The matcher DSL fields (`host`, `port`, `httpMethod`, `path`, `scheme`,
`procName`) support glob wildcards (`*` zero-or-more, `?` exactly one).
For structured plugins (httpclient parses URLs into host/port/path),
plugin-side comparison is the planned upgrade; today the matcher walks
the call's fingerprint string as a coarse fallback. Closures remain
the unconditional escape hatch.

### `restrict` — ceiling on `allow`

```nim
sandbox:
  # `allow` lists what the sandbox PERMITS. `restrict` is a CEILING
  # that shrinks the effective permission set down to calls that fall
  # inside it. Pair a broad `allow` with a narrow `restrict` to get
  # "permit anything httpclient intercepts, but only under 127.0.0.*."
  allow(httpclientPlugin)                              # broad
  restrict(httpclientPlugin, M(host = "127.0.0.*"))    # ceiling

  # A call passes iff some `allow` matches AND, if any `restrict` is
  # configured for the plugin, some `restrict` matches too. With no
  # `allow` registered, `restrict` alone authorizes nothing — it
  # filters the permission set, it does not grant.
```

Use `restrict` to bound a sandbox's blast radius. Bigfoot's mental
model: `allow` is the permit list; `restrict` is the ceiling that
inner blocks cannot widen. Tripwire today is single-scope, so the
ceiling and the permit list collapse to "allow ∩ restrict at call
time" — but the framing extends naturally to nested sandboxes when
they land.

### `guard` — warn vs error

```nim
sandbox:
  # Default: every unmocked call that doesn't match `allow` raises.
  # currentVerifier().firewallMode == fmError

  # Bigfoot-style soft mode: warn to stderr, then proceed via passthrough.
  guard(currentVerifier(), fmWarn)
```

Project-wide via `tripwire.toml`:

```toml
[tripwire.firewall]
allow = ["mock"]    # plugin-name shorthands
guard = "warn"      # or "error" (default)
```

Tripwire defaults to `error` to preserve Guarantee 1 (every external
call is pre-authorized); flip to `warn` per-sandbox or in
`tripwire.toml` for bigfoot's softer default.

### Chronos httpclient (firewall-only) plugin

Tripwire ships a chronos httpclient plugin under `-d:chronos` that
enforces **Guarantee #1 only** — every external chronos HTTP call must
be `allow`'d (or `restrict`-ceiling'd). Mocking is NOT supported on
this surface; use closure-based DI at your transport boundary for G2/G3
coverage (e.g. inject an `HttpSender` closure into your REST client).

Why firewall-only: chronos's `HttpClientResponse` carries a private
`state` field with no public constructor, so a synthetic-response mock
plugin would require `cast` or `unsafeNew` (forbidden in any consumer
that enforces the same idiom rules tripwire targets). The firewall
path sidesteps this entirely — it never constructs a response, only
decides whether the call may proceed.

```nim
import tripwire
import chronos
import chronos/apps/http/httpclient
import tripwire/plugins/chronos_httpclient as nfchronos

sandbox:
  # Authorize loopback only.
  allow(nfchronos.chronosHttpPluginInstance, M(host = "127.0.0.1"))
  let session = HttpSessionRef.new()
  let req = HttpClientRequestRef.post(
    session, "http://127.0.0.1:" & $port & "/health", body = "").get()
  let resp = waitFor req.send()    # firewall passes through to chronos
  # ...
```

Intercepted surfaces: `send(req)` (the network boundary inside chronos's
request lifecycle) and `fetch(session, url)` (the URL-only convenience
GET). The plugin does not intercept `fetch(req)` because its body
internally calls `send`, which our `send` TRM already covers.

Auto-registers when `-d:chronos` is set; consumers without chronos see
no plugin and no compile cost.

### Per-test sugar

```nim
firewallTest "fetches user", [httpclientPlugin], fmError:
  # body runs inside a sandbox with allow(httpclientPlugin) and
  # firewallMode = fmError already configured.
  ...
```

## Documentation

- [`docs/quickstart.md`](docs/quickstart.md) — install, activate, first test.
- [`docs/plugin-authoring.md`](docs/plugin-authoring.md) — 13 Plugin Authoring Rules.
- [`docs/design/v0.md`](docs/design/v0.md) — full design (140+ pages).

## License

MIT.
