# tripwire v0 — quickstart

This walkthrough takes you from a fresh clone to a passing test in
under five minutes. If any step fails, jump to
[`docs/plugin-authoring.md`](plugin-authoring.md) for the full design
or file an issue with the exact command + output.

## 1. Install

```bash
nimble install tripwire
```

tripwire requires **Nim >= 2.0** and **parsetoml >= 0.7**. Chronos and
unittest2 are optional; the framework ships working matrix cells for
both but they are gated behind `-d:chronos` / `-d:tripwireUnittest2`.

## 2. Activate

Consumer projects must add **two lines** to their test `config.nims`:

```nim
# tests/config.nims
--import:"tripwire/auto"
--define:"tripwireActive"
--warning:UnusedImport:off
```

The `--import:"tripwire/auto"` flag injects the umbrella module into
every test TU so plugin TRMs become in-scope for pattern matching.
`-d:tripwireActive` gates that injection AND tells the public facade
(`import tripwire`) the user really did activate the framework.

Without activation, `import tripwire` fails at compile time with a
clear message (Defense 1). The escape hatch for tooling that needs
to reference tripwire symbols without running tests is
`-d:tripwireAllowInactive`.

## 3. First test

```nim
# tests/test_my_service.nim
import tripwire
import tripwire/plugins/httpclient as nfhttp
import std/[httpclient, options, tables]

test "fetches user data":
  sandbox:
    let c = newHttpClient()
    nfhttp.expectHttp get(c, "http://api.example.com/users/1"):
      respond:
        status: 200
        body: """{"id":1}"""
    let r = c.get("http://api.example.com/users/1")
    check r.status == "200"
    check r.body.contains("\"id\":1")
    nfhttp.assertHttp get(c, "http://api.example.com/users/1"):
      responded:
        status: 200
```

Run it:

```bash
nim c -r --define:tripwireActive --import:tripwire/auto tests/test_my_service.nim
```

Or through nimble once you declare a test task. The test passes
if all three guarantees hold:

1. Every external call is **pre-authorized** (the `expectHttp` block
   registered the mock before the `get` fired).
2. Every recorded interaction is **explicitly asserted** (the
   `assertHttp` block matched the recorded call).
3. Every registered mock is **consumed** (the mock was popped when
   the call matched).

## 4. What's not supported in v0

The framework enforces a narrow contract. These boundaries are known
scope cuts, surfaced here so you don't discover them by surprise:

- **User-code threading** (`--threads:on` on worker threads): TRMs
  on worker threads crash the process. The tripwire compilation is
  thread-safe (threadvar verifier stacks) but the framework does not
  support parallel test bodies in v0.
- **`asyncCheck` inside tests**: use `waitFor` instead. Leaked
  Futures raise `PendingAsyncDefect` at teardown (Defense 6).
- **FFI calls** (`{.importc.}`, `{.dynlib.}`, `{.header.}`): tripwire
  intercepts Nim-source calls only. The libc-level firewall arrives
  in v0.2 (`-d:tripwireAuditFFI` already accepts the stub in v0).
- **Windows guard mode**: the failure hardening that makes bigfoot
  kill-tests-on-leak under Linux/macOS hasn't been ported yet.

See [`docs/plugin-authoring.md`](plugin-authoring.md) for writing
plugins and [`docs/concepts.md`](concepts.md) (if present) for the
scope / FFI boundary explained at length.
