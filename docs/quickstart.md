# tripwire v0 — quickstart

This walkthrough takes you from a fresh clone to a passing test in
under five minutes, then turns the firewall on so unmocked calls
inside or outside your sandbox fail in a way you can act on.

For the elevator pitch see [`README.md`](../README.md). For writing
your own plugin see [`docs/plugin-authoring.md`](plugin-authoring.md).

## 1. Install

```bash
nimble install tripwire
```

`tripwire.nimble` requires `nim >= 2.0` and `parsetoml >= 0.7.0`. The
internal test matrix runs on Nim 2.2.x (Cells 1 through 7 plus the
standalone cells 5b/5c/5d/5e and 6/6b/6c/6d in `tripwire.nimble`);
other 2.x compilers are not part of the matrix.

Two optional integrations are off by default and gate at compile time:

- **chronos** (`-d:chronos`): adds the chronos httpclient firewall-only
  plugin. The opt-in test cells (6, 6b, 6c) require
  `TRIPWIRE_TEST_CHRONOS=1` because chronos is not in `requires`.
- **websock** (`-d:websock`): adds the websock-client firewall-only
  plugin (websock transitively requires chronos). The opt-in test
  cell (6d) requires `TRIPWIRE_TEST_WEBSOCK=1`.

`-d:tripwireUnittest2` swaps the integration shim to `unittest2` so
tripwire's per-test verifier hooks compose with `unittest2.test`
instead of `std/unittest.test`.

## 2. Activate

Consumer projects must add **two lines** to their test `config.nims`:

```nim
# tests/config.nims
--import:"tripwire/auto"
--define:"tripwireActive"
--warning:UnusedImport:off
```

`--import:"tripwire/auto"` injects the umbrella module into every test
TU so plugin TRMs become in-scope for pattern matching.
`-d:tripwireActive` gates that injection AND tells the public facade
(`import tripwire`) that the user really did activate the framework.

Without activation, `import tripwire` fails at compile time with a
clear message (Defense 1). The escape hatch for tooling that needs to
reference tripwire symbols without running tests is
`-d:tripwireAllowInactive`.

## 3. Your first test

```nim
# tests/test_my_service.nim
import tripwire
import tripwire/plugins/httpclient as nfhttp
import std/[httpclient, options, tables, unittest]

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

Or through `nimble test` once you declare a test task. The test passes
if all three guarantees hold:

1. **G1, pre-authorization.** The `expectHttp` block registered the
   mock before `c.get(...)` fired.
2. **G2, explicit assertion.** The `assertHttp` block matched the
   recorded call.
3. **G3, mock consumption.** The mock was popped when the call
   matched.

Drop the `expectHttp` block and the test fails with
`UnmockedInteractionDefect: get(...)`. Drop the `assertHttp` block
and it fails with `UnassertedInteractionsDefect`. Drop `c.get(...)`
but keep the `expectHttp` and the mock goes unused, raising
`UnusedMocksDefect`. That is G1, G2, and G3 firing.

`import tripwire/plugins/httpclient as nfhttp` is required explicitly:
the umbrella gives you the plugin's TRM rewrites, but the
`expectHttp` and `assertHttp` macros live in the plugin module
itself.

## 4. Firewall: allow, restrict, guard

`expect`/`assert` is the strict path: every external call gets a
synthetic mock. For tests that need the real implementation to run
inside the sandbox (a real DNS lookup, a real `127.0.0.1` HTTP call,
a real subprocess), the **firewall API** authorizes specific calls
without mocking them.

```nim
import tripwire
import tripwire/plugins/httpclient as nfhttp
import tripwire/plugins/osproc as nfosproc

sandbox:
  # Plugin shorthand: any call routed through this plugin passes.
  allow(nfosproc.osprocPluginInstance)

  # Matcher DSL: only requests to *.example.com pass.
  allow(nfhttp.httpclientPluginInstance, M(host = "*.example.com"))

  # Closure escape hatch: any predicate over (procName, fingerprint).
  allow(nfhttp.httpclientPluginInstance,
    proc(p, fp: string): bool {.gcsafe, raises: [].} =
      "127.0.0.1" in fp)
```

`restrict` is a **ceiling** on `allow`. A call passes the firewall iff
some `allow` entry matches AND, if any `restrict` is configured for
that plugin, some `restrict` entry also matches. `restrict` alone
authorizes nothing; it filters allows, it does not grant.

```nim
sandbox:
  # Permit anything httpclient intercepts...
  allow(nfhttp.httpclientPluginInstance)
  # ...but only for hosts matching 127.0.0.*.
  restrict(nfhttp.httpclientPluginInstance, M(host = "127.0.0.*"))
```

To flip a single sandbox from "unmocked = raise" to "unmocked = log
and pass through," call `guard(currentVerifier(), fmWarn)`:

```nim
sandbox:
  guard(currentVerifier(), fmWarn)
  # Calls without a matching mock now write a stderr line and proceed
  # via passthrough instead of raising UnmockedInteractionDefect.
  ...
```

`fmError` (the default) is the three-guarantees posture. `fmWarn`
mirrors bigfoot's `guard = "warn"` lane and is intended for triage,
not for committed test code.

## 5. Project-wide firewall config (`tripwire.toml`)

Per-sandbox `allow`/`restrict`/`guard` covers what runs *inside* your
sandbox. The **project-wide firewall** covers what happens when a
TRM-intercepted call fires *outside* any sandbox: code that imports a
plugin-instrumented module but runs outside a `sandbox:` block, e.g.
during application startup or in a binary that links the test build.

Configure it in `tripwire.toml` at your project root (or wherever
`TRIPWIRE_CONFIG` points to). Discovery walks up from the working
directory, stopping at the first `.nimble`:

```toml
[tripwire.firewall]
# Default disposition for every plugin that does not have its own key.
# "error" raises LeakedInteractionDefect; "warn" tries passthrough.
default = "error"

# Per-plugin overrides. Names are exact ("httpclient" and
# "chronos_httpclient" are separate keys).
httpclient = "warn"
chronos_httpclient = "error"

# Optional: blanket-allow these plugins regardless of mode.
allow = ["mock"]
```

Resolution at call time: the plugin name is looked up in the
per-plugin overrides; if absent, `default` is used. Defaults are
`default = "error"` and an empty per-plugin map.

Three things can happen to a call that fires outside any sandbox:

- Resolved mode is `error`. The call raises **`LeakedInteractionDefect`**
  with the firing thread, plugin, proc, and call site.
- Resolved mode is `warn` and the plugin **supports passthrough**.
  Of the built-ins this is currently only `mock`; the other built-ins
  default to no-passthrough outside-sandbox regardless of whether
  they are full-mock (`httpclient`, `osproc`) or firewall-only
  (`chronos_httpclient`, `websock`). The call writes a stderr line
  (`tripwire(guard=warn): unmocked <plugin>.<proc> at ...`) and
  proceeds to the real implementation.
- Resolved mode is `warn` and the plugin **does not support
  passthrough** (every built-in except `mock`: `httpclient`, `osproc`,
  `chronos_httpclient`, `websock`). The call raises
  **`OutsideSandboxNoPassthroughDefect`** with this message body:

  ```
  plugin '<NAME>' doesn't support outside-sandbox passthrough for
  '<PROC>' at <FILE>:<LINE>; install a sandbox to mock this call,
  or switch to error mode ([tripwire.firewall].<NAME>='error' or
  [tripwire.firewall].default='error') to raise the standard
  LeakedInteractionDefect instead
  ```

  (The actual stderr output also carries tripwire's standard
  FFI-scope footer reminding you that `{.importc.}` / `{.dynlib.}` /
  `{.header.}` calls are out of scope.) The remediation is in the
  message: install a sandbox and mock the call, or flip the mode to
  `error` so you get the standard `LeakedInteractionDefect` raise
  site instead of the no-passthrough lane.

To `try`/`except OutsideSandboxNoPassthroughDefect` in your code,
`import tripwire/errors` directly. The defect type is intentionally
not on the `tripwire/auto` umbrella (a Nim 2.2.8 export-list ceiling;
see `src/tripwire/auto_internal_exports.nim` for the constraint).

**Migration note.** A4'''.5 replaced the earlier single-scalar form
(`guard = "warn"|"error"` under `[tripwire.firewall]`) with the
per-plugin form documented above. If your `tripwire.toml` still has a
literal `guard` key, you will see one stderr line per
`reloadConfig()` cycle:

```
tripwire: ignoring legacy [tripwire.firewall].guard key (renamed to
`default` in A4'''.5; treated as per-plugin override for plugin name
'guard', which does not exist)
```

Rename `guard` to `default`; per-plugin lines (e.g. `httpclient =
"warn"`) keep the same shape.

## 6. What is not in v0

The framework enforces a narrow contract. These boundaries are known
scope cuts:

- **FFI calls** (`{.importc.}`, `{.dynlib.}`, `{.header.}`): tripwire
  intercepts Nim-source calls only. The libc-level firewall arrives
  in v0.2 (`-d:tripwireAuditFFI` already accepts the stub in v0).
- **New surfaces require a plugin.** Adding tripwire coverage for a
  module not on the built-in list (`mock`, `httpclient`, `osproc`,
  `chronos_httpclient`, `websock`) means writing a plugin. See
  [`docs/plugin-authoring.md`](plugin-authoring.md) for the rules
  and a worked example.

For per-release breaking changes and migration recipes see
[`CHANGELOG.md`](../CHANGELOG.md). For the v0.3 roadmap see
[`docs/roadmap-v0.3.md`](roadmap-v0.3.md).
