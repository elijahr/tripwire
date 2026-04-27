# tripwire

Test mocking framework for Nim that refuses to lie about coverage.

`unittest.mock` and friends pass when the test says nothing. tripwire
fails the test when the test says nothing. Every external call must be
pre-authorized, every recorded interaction must be asserted, and every
registered mock must be consumed. Violations raise non-catchable
defects that abort the test binary with a stack trace naming the
offending call.

Nim port of [axiomantic/bigfoot](https://github.com/axiomantic/bigfoot).
Bigfoot is the canonical UX reference; the firewall vocabulary (`allow`,
`restrict`, `M(...)`, `guard`) is taken directly from it.

## What tripwire is, and isn't

- **Is:** a strict TRM-driven test mocking layer for Nim 2.x. Catches
  unmocked I/O at compile-of-test time, not at code review time.
- **Is:** capital-preservation infrastructure. The host project
  (paperplanes) trades real money; "the test passed" lying is not
  acceptable.
- **Is:** scoped to **Nim source calls**. `{.importc.}`, `{.dynlib.}`,
  `{.header.}` are NOT intercepted (an opt-in audit lists them).
- **Isn't:** a stub library or recording proxy. No record, replay, or
  VCR mode.
- **Isn't:** load-bearing on permissive defaults. The default is "deny
  every call that isn't pre-authorized."
- **Isn't:** v1.0. See the alpha banner below.

## Three guarantees (30 seconds)

1. **G1 - pre-authorization.** Every external call routed through a
   tripwire plugin must have a queued mock OR a matching `allow`.
   Otherwise the call site raises `UnmockedInteractionDefect` BEFORE
   the network/process/socket is touched.
2. **G2 - explicit assertion.** Every interaction recorded on the
   timeline must be matched by an `assert*` block. Unasserted
   interactions raise `UnassertedInteractionsDefect` at sandbox exit.
3. **G3 - mock consumption.** Every mock queued by an `expect*` block
   must be consumed by a real call. Unused mocks raise
   `UnusedMocksDefect` at sandbox exit.

Defects derive from `Defect`, not `CatchableError`. Test code cannot
swallow them.

## Activate (30 seconds)

Install:

```bash
nimble install tripwire
```

Add two lines to your test config (`tests/config.nims`):

```nim
--import:"tripwire/auto"
--define:"tripwireActive"
```

The first injects the umbrella module into every test TU so plugin
TRMs are in scope. The second gates activation. Without it,
`import tripwire` fails at compile time (Defense 1) with a message
pointing at this README.

A first test:

```nim
# tests/test_user.nim
import tripwire
import tripwire/plugins/httpclient as nfhttp
import std/[httpclient, options, tables, unittest]

test "fetches user data":
  sandbox:
    let c = newHttpClient()
    nfhttp.expectHttp get(c, "http://api/u/1"):
      respond:
        status: 200
        body: """{"id":1}"""
    let r = c.get("http://api/u/1")
    check r.status == "200"
    check r.body.contains("\"id\":1")
    nfhttp.assertHttp get(c, "http://api/u/1"):
      responded:
        status: 200
```

Run it:

```bash
nim c -r tests/test_user.nim
```

Drop the `expectHttp` block and the test fails with
`UnmockedInteractionDefect: get(...)`. Drop the `assertHttp` block and
it fails with `UnassertedInteractionsDefect`. That's G1 and G2 firing.

## Plugin coverage

| Plugin | Type | Guarantees | Trigger |
|--------|------|-----------|---------|
| `mock` | Full mock | G1 + G2 + G3 | always on |
| `httpclient` (`std/httpclient`) | Full mock | G1 + G2 + G3 | always on |
| `osproc` (`std/osproc`) | Full mock | G1 + G2 + G3 | always on |
| `chronos_httpclient` | Firewall-only | G1 | `-d:chronos` |
| `websock` | Firewall-only | G1 | `-d:websock` |

**Full mock** plugins synthesize responses inside the test (no real
I/O). **Firewall-only** plugins enforce G1 only and pass through to
the real implementation when `allow`'d. Mock chronos/websock traffic
at your transport boundary via closure-based DI (e.g. inject an
`HttpSender` closure into a REST client). The firewall-only shape
exists because chronos's `HttpClientResponse.state` and websock's
connect path have no public constructors that can be synthesized
without `cast` or `unsafeNew`, both forbidden in tripwire and in its
consumer.

The chronos plugin intercepts all three on-wire surfaces: `send(req)`,
`fetch(session, url)`, and `fetch(req)`. The third closed a silent G1
bypass in v0.0.2 (`req.fetch()` reaching the network without firewall
consultation). The websock plugin intercepts via a
`nfwebsockConnect(uri)` wrapper rather than `WebSocket.connect(uri)`,
because Nim 2.2.8's TRM matcher does not fire on typedesc receivers.

## Firewall mode

`expect`/`assert` is the strict path. For tests that genuinely need
the real implementation to run inside the sandbox, the firewall API
authorizes specific calls without mocking them.

```nim
sandbox:
  # Plugin shorthand: any call routed through dnsPlugin passes.
  allow(dnsPlugin)

  # Matcher DSL: only requests to *.example.com pass.
  allow(httpclientPluginInstance, M(host = "*.example.com"))

  # Closure escape hatch: any predicate over (procName, fingerprint).
  allow(socketPlugin, proc(p, fp: string): bool =
    fp.contains("127.0.0.1"))
```

`restrict` is a ceiling on `allow`: a call passes iff some `allow`
matches AND, if any `restrict` is configured, some `restrict` matches
too. `restrict` alone authorizes nothing.

`guard(currentVerifier(), fmWarn)` flips the per-sandbox mode from
"unmocked = raise" to "unmocked = log to stderr and pass through,"
matching bigfoot's `guard = "warn"`. tripwire defaults to `fmError`
because Guarantee 1 is the point.

Per-test sugar (`firewallTest "name", [plugins], mode: body`) opens a
sandbox, blanket-`allow`s each plugin, and sets the mode in one step.
Project-wide config lives in `tripwire.toml` under `[tripwire.firewall]`:
`allow = [...]` blanket-allows the listed plugins, `default =
"warn"|"error"` sets the project-wide outside-sandbox disposition, and
per-plugin sibling keys (`<plugin-name> = "warn"|"error"`) override the
default for individual plugins. See
[`docs/quickstart.md`](docs/quickstart.md) for the resolution rules and
the message format you will see when a firewall-only plugin (e.g.
`chronos_httpclient`) fires outside any sandbox under `warn`.

## v0.0.x is alpha

tripwire is pre-1.0. Breaking changes ship in any pre-1.0 release;
each release's `CHANGELOG.md` includes a migration recipe. As of
v0.0.2:

- The framework has been validated against one consumer
  (paperplanes) and the seven-cell internal matrix (refc/orc/arc, sync,
  unittest2, chronos opt-in, threads). It has NOT been validated
  against any other consumer project.
- v0.0.3 will require `--gc:orc` or `--gc:arc` for the threads module
  (refc + threads is rejected at compile time today via the F2
  build probe).
- The `TRIPWIRE_FFI_*` env vars were removed in v0.0.2; FFI audit
  configuration is compile-define-only. See `CHANGELOG.md`.

## Inspirations

[axiomantic/bigfoot](https://github.com/axiomantic/bigfoot) is the
design source. Three-guarantee model, plugin shape, firewall
vocabulary, and the loud-failure ethos all come from there. Defect
text was tuned independently to match Nim's stack-trace conventions.

## Status and development

- [`CHANGELOG.md`](CHANGELOG.md) - per-release notes and migration
  recipes.
- [`docs/quickstart.md`](docs/quickstart.md) - install, activate,
  first test.
- [`docs/plugin-authoring.md`](docs/plugin-authoring.md) - the
  plugin authoring rules. Required reading before writing a new
  plugin.

## License

MIT.
