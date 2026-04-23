# nimfoot

Test mocking framework for Nim, enforcing the **three guarantees**:

1. Every external call is pre-authorized.
2. Every recorded interaction is explicitly asserted.
3. Every registered mock is consumed.

Violations raise `{.NimfootDefect.}`s that are NOT catchable by user
code — they abort the test binary with a stack trace that names the
offending interaction.

## !! SCOPE

**nimfoot intercepts Nim source calls only.** FFI (`{.importc.}`,
`{.dynlib.}`, `{.header.}`) is NOT intercepted in v0. This is an
intentional scope cut: the libc-level firewall (bigfoot's v3 layer)
arrives in v0.2 via `-d:nimfootAuditFFI` (stub present in v0).

Every defect message includes an FFI-scope footer pointing at
`docs/concepts.md#scope`; if your test reports `UnmockedInteraction`
for a call you thought was mocked, re-check whether it crosses the
Nim/FFI boundary.

## Status: v0 (pre-release)

- Tracks A–H landed.
- Matrix green on refc + orc across sync + unittest2 backends.
- chronos cell opt-in (`-d:chronos`); requires the chronos package
  in the consumer's `nimble requires`.

See [`docs/quickstart.md`](docs/quickstart.md) for the full walkthrough.

## Install

```bash
nimble install nimfoot
```

## Minimal example

```nim
import nimfoot
import nimfoot/plugins/httpclient as nfhttp
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
