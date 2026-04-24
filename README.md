# tripwire

Test mocking framework for Nim, enforcing the **three guarantees**:

1. Every external call is pre-authorized.
2. Every recorded interaction is explicitly asserted.
3. Every registered mock is consumed.

Violations raise `{.TripwireDefect.}`s that are NOT catchable by user
code — they abort the test binary with a stack trace that names the
offending interaction.

Nim adaptation of [bigfoot](https://github.com/axiomantic/bigfoot) (pytest).

> **ALPHA** — tripwire is pre-1.0. Breaking changes may ship in any
> minor release. Each release's CHANGELOG includes explicit migration
> steps. v0.2 removes the `TRIPWIRE_FFI_*` environment variables
> (config is now compile-define only) and the new `tripwire/threads`
> module requires `--gc:orc` or `--gc:arc` (refc is rejected at
> compile time); see [`CHANGELOG.md`](CHANGELOG.md) for the migration
> recipe.

## v0.2 new capabilities

- `tripwireThread` / `withTripwireThread` — verifier-inheriting thread
  primitives so child threads see the parent sandbox's mock queue and
  timeline (design §3).
- `asyncCheckInSandbox` — opt-in `asyncdispatch` Future registration;
  `drainPendingAsync` on sandbox teardown raises `PendingAsyncDefect`
  for any Future still in flight (design §4).
- Scoped FFI auto-discovery — real `{.importc.}` / `{.importcpp.}` /
  `{.importobjc.}` / `{.importjs.}` pragma scanner replacing the
  env-var-driven v0 stub (Defense 2 Part 3, design §5).
- Named sandbox overload — `sandbox "label": body` surfaces the label
  in defect messages for faster triage (design §6.3).

See [`CHANGELOG.md`](CHANGELOG.md) for the full migration recipe.

## !! SCOPE

**tripwire intercepts Nim source calls only.** FFI (`{.importc.}`,
`{.dynlib.}`, `{.header.}`) is NOT intercepted in v0. This is an
intentional scope cut: the libc-level firewall (bigfoot's v3 layer)
arrives in v0.2.

An opt-in FFI *audit* ships via `-d:tripwireAuditFFI`. When set,
tripwire auto-scopes to the project path (via Nim's
`std/compilesettings.querySetting(projectPath)`) at compile time and
emits a `{.hint.}` listing every `{.importc.}`, `{.importcpp.}`,
`{.importobjc.}`, and `{.importjs.}` pragma it finds, with per-file
counts and a grand total. v0.2 replaced the v0.1
`TRIPWIRE_FFI_SCAN_PATHS` / `TRIPWIRE_FFI_TRANSITIVE_PATHS` env vars
with compile-time auto-discovery (Defense 2 Part 3, design §5). To
extend the scan beyond the project to nimble-managed dependencies,
set `-d:tripwireAuditFFITransitive` (which walks the nimble deps
tree); the `-d:tripwireAuditFFIExtraRequires="pkg1,pkg2"` escape
hatch adds extra package names to that walk and is a no-op unless
`-d:tripwireAuditFFITransitive` is also set.
See [`CHANGELOG.md`](CHANGELOG.md) for the v0.1 → v0.2 migration
recipe.

Every defect message includes an FFI-scope footer pointing at
`docs/concepts.md#scope`; if your test reports `UnmockedInteraction`
for a call you thought was mocked, re-check whether it crosses the
Nim/FFI boundary.

## Status: v0.2 (pre-release)

- Tracks A–H landed in v0; v0.2 adds WI1-WI5 (see `CHANGELOG.md`).
- Matrix green across 7 cells: refc + orc × sync + unittest2 (cells
  1-4), standalone `test_osproc_arrays` under orc (cell 5),
  orc+chronos opt-in (cell 6), arc+threads (cell 7), plus a
  separate negative refc+threads build probe (F2 guard).
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

## Documentation

- [`docs/quickstart.md`](docs/quickstart.md) — install, activate, first test.
- [`docs/plugin-authoring.md`](docs/plugin-authoring.md) — 13 Plugin Authoring Rules.
- [`docs/design/v0.md`](docs/design/v0.md) — full design (140+ pages).

## License

MIT.
