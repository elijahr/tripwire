# Plugin authoring — the 13 Rules

A **tripwire plugin** is a Nim module that intercepts one or more
procs from another library and lets tests mock their return values.
The built-in plugins (`mock`, `httpclient`, `osproc`) are the
reference implementations; this guide distils the 13 authoring rules
that make a plugin safe, testable, and TRM-engine-compatible.

Every plugin ships:

1. A `Plugin` subtype (`ref object of Plugin`) with a singleton instance.
2. One or more `MockResponse` subtypes (`ref object of MockResponse`)
   carrying the data your TRM returns to callers.
3. One **term-rewriting-macro template** per proc shape you intercept.
4. The TRM body invokes `tripwireInterceptBody` (or its plugin-friendly
   sibling `tripwirePluginIntercept`) so the three-guarantee lifecycle
   runs on every rewritten call.

The reference skeleton (from design §5.3.1) is:

```nim
template mockedProcTRM*(a: int, b: string): Response
  {.pattern: mockedProc(a, b), fingerprint: nfFingerprintMockedProc.} =
  tripwireInterceptBody(mockedProcPlugin, "mockedProc",
    fingerprintOf("mockedProc", @[$a, $b]),
    MockedProcResponse):
    {.noRewrite.}:
      mockedProc(a, b)   # real call (spy/passthrough)
```

Every rule below references the file in `src/tripwire/plugins/` where
the built-ins demonstrate it.

## Rule 1 — Reproduce the wrapped proc's arity and defaults exactly

The TRM must have the **same formal parameters** as the wrapped proc,
including default values, in the same order. Nim's TRM pattern matcher
matches on the declared shape; a missing default makes the call fall
through to the real proc silently.

Example (`plugins/httpclient.nim`): `request` takes `headers:
HttpHeaders = nil` — **not** `newHttpHeaders()`. If you write
`newHttpHeaders()` as the default, tests that omit the argument call
the real network.

## Rule 2 — Use distinct types by their **declared name**, not an alias

`std/net.Port` is a distinct uint16; the TRM must write `Port` (not
`uint16`). Nim's pattern matcher compares type symbols, not their
underlying representation.

## Rule 3 — One TRM per concrete container shape, plus a fallback trap

Arrays and openArrays are not the same shape for pattern matching.
`plugins/osproc.nim` emits TRMs for `seq[string]`, `array[0, string]`
through `array[8, string]`, AND a fallback `openArray[string]` trap
that raises `UnmockableContainerDefect` (Defense 5) so a caller using
`toOpenArray` can't silently escape the mock.

## Rule 4 — Use `{.noRewrite.}:` statement-blocks for spy passthrough

Inside a TRM body, if you need to call the original proc (spy mode,
or the plugin passes through unmocked calls), wrap the real call in
`{.noRewrite.}:`. Without this, the TRM re-enters itself infinitely.

## Rule 5 — Construct Futures via `tripwire/futures`, not inline `complete`

Chronos 4.x has a lexical-scoping bug (`spike #6 Q4`) where
`complete(fut, value)` inside a template body crashes the compiler.
Delegate to `makeCompletedFuture` from `tripwire/futures.nim`, which
wraps the complete call in a runtime proc that Nim's macro engine
handles cleanly.

## Rule 6 — The TRM body calls `tripwireCountRewrite()` first

Defense 3 enforces the ~15-rewrites-per-TU cap. The
`tripwireInterceptBody` / `tripwirePluginIntercept` combinators handle
this for you — if you write a custom body, call
`tripwireCountRewrite()` as the first statement.

## Rule 7 — Every TRM body checks the current verifier

`tripwireInterceptBody` does this: if `currentVerifier()` is nil → raise
`LeakedInteractionDefect` (Defense 6). If the verifier is popped but
still current (generation mismatch), raise `PostTestInteractionDefect`.
Hand-rolled TRM bodies MUST replicate these checks — `test_intercept.nim`
enforces them.

## Rule 8 — Avoid `{.push noRewrite.}` at module scope

`noRewrite` is a per-statement pragma; pushing it globally shadows
*all* TRM rewrites in the module, including the plugin's own. Use
`{.noRewrite.}:` statement-block form exclusively (see Rule 4).

## Rule 9 — Multisync procs need **two** TRMs

`std/httpclient.request` has sync and async forms sharing most of a
signature. Write **two** separate TRMs (one for `HttpClient`, one for
`AsyncHttpClient`), because Nim's TRM matcher won't unify them. See
`plugins/httpclient.nim` for the reference pair.

## Rule 10 — Anonymous tuple return types must be spelled exactly

A proc returning `tuple[a: string, b: int]` needs the TRM to declare
the *same* tuple syntax. Named tuples do NOT match anonymous tuples
at the pattern level. `std/osproc.execCmdEx` returns
`tuple[output: string, exitCode: int]` — the TRM must use that
spelling verbatim.

## Rule 11 — `extern: "nosp$1"` → `tripwireRaw*` helper prefix

When a plugin wraps a proc that already has a C-level name (e.g.,
`{.extern: "nosp$1".}`), the tripwire-local helper that stands in for
the real impl in spy mode is named `tripwireRaw<ProcName>`. This
prevents link-time collisions with the real symbol. `plugins/osproc.nim`
demonstrates the pattern for `execProcess`.

## Rule 12 — Fire-through is the default; opt out via `{.noRewrite.}:`

A plugin's TRM fires on every matching call unless the caller wraps
the call in `{.noRewrite.}:`. This is the inverse of some mocking
frameworks. Users who need to temporarily call the real impl in a
test (e.g., for a warm-up fixture) use `{.noRewrite.}:` at the call
site.

## Rule 13 — For httpclient, intercept at `request`, not at wrappers

`httpclient.get`, `httpclient.post`, `httpclient.put`, etc. all
delegate to `httpclient.request`. The plugin intercepts `request`
only, and the wrapper canonicalization DSL (`expectHttp get(c, url):`)
rewrites user `expect` blocks to register against `request`. This
keeps the plugin small (two TRMs, sync + async) and guarantees the
mock matches regardless of which wrapper the user called.

---

## Minimal plugin example

A complete plugin wrapping a single user-declared proc:

```nim
# myservice_plugin.nim
import tripwire/[types, errors, timeline, sandbox, verify, intercept,
                cap_counter, macros as nfmacros]
import tripwire/plugins/plugin_intercept
import std/[tables, options]

# 1) Plugin type + singleton
type
  MyServicePlugin = ref object of Plugin
  MyServiceResp = ref object of MockResponse
    value: int

method realize*(r: MyServiceResp): int = r.value

let myPlugin* = MyServicePlugin(name: "myservice", enabled: true)
registerPlugin(myPlugin)

# 2) The user-facing proc we want to mock
proc fetchCount*(url: string): int =
  # Real implementation (network, DB, whatever)
  raise newException(IOError, "real fetchCount not available in tests")

# 3) TRM that intercepts it
template fetchCountTRM*(url: string): int
  {.pattern: fetchCount(url), fingerprint: fingerprintFetchCount.} =
  tripwirePluginIntercept(myPlugin, "fetchCount",
    fingerprintOf("fetchCount", @[url]),
    MyServiceResp):
    {.noRewrite.}:
      fetchCount(url)   # spy body — real impl
```

Users write tests against it as:

```nim
sandbox:
  let m = newMock("fetchCount", fingerprintOf("fetchCount", @["u"]),
    MyServiceResp(value: 42), instantiationInfo())
  registerMock(currentVerifier(), "myservice", m)
  check fetchCount("u") == 42
  currentVerifier().timeline.markAsserted(
    currentVerifier().timeline.entries[0])
```

For a higher-level DSL (`expect fetchCount("u"): respond value: 42`),
see the `mockable`/`expect`/`assert` macros in `plugins/mock.nim` — the
same pattern generalizes to any plugin that accepts value-typed args.

## Further reading

- **Design §5.1**: plugin type hierarchy and lifecycle.
- **Design §5.3.1**: TRM body skeleton, spy-or-raise mode.
- **Design §5.8**: the 13 rules indexed by footnote (authoritative source).
- **Design §12.2**: why httpclient intercepts at `request` depth.
- **`src/tripwire/plugins/plugin_intercept.nim`**: the combinator
  plugin TRMs are expected to wrap their bodies in.
