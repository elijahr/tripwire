# Plugin authoring

A **tripwire plugin** is a Nim module that intercepts one or more
procs from another library and lets tests mock or firewall those
calls. The built-in plugins (`mock`, `httpclient`, `osproc`,
`chronos_httpclient`, `websock`) are the reference implementations;
this guide distils the rules that make a plugin safe, testable, and
TRM-engine-compatible.

Two plugin shapes exist:

- **Full-mock plugins** (`mock`, `httpclient`, `osproc`) synthesize
  responses inside the test. They enforce all three guarantees: G1
  (pre-authorization), G2 (explicit assertion), G3 (mock consumption).
- **Firewall-only plugins** (`chronos_httpclient`, `websock`) enforce
  G1 only. They never construct a synthetic response; instead, they
  pass through to the real implementation when an `allow` rule
  matches and raise `UnmockedInteractionDefect` otherwise. See
  Rule 14 for when this shape is required.

Every plugin ships:

1. A `Plugin` subtype (`ref object of Plugin`) with a singleton instance.
2. One or more `MockResponse` subtypes (`ref object of MockResponse`)
   carrying the data your TRM returns to callers (full-mock only;
   firewall-only plugins still declare a `MockResponse` subtype but its
   `realize` path is unreachable in normal use).
3. One **term-rewriting-macro template** per proc shape you intercept.
4. The TRM body invokes `tripwireInterceptBody` (or its plugin-friendly
   sibling `tripwirePluginIntercept`) so the three-guarantee lifecycle
   runs on every rewritten call.

The reference skeleton:

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
HttpHeaders = nil`, **not** `newHttpHeaders()`. If you write
`newHttpHeaders()` as the default, tests that omit the argument call
the real network.

## Rule 2 — Use distinct types by their **declared name**, not an alias

`std/net.Port` is a distinct uint16; the TRM must write `Port`, not
`uint16`. Nim's pattern matcher compares type symbols, not their
underlying representation.

## Rule 3 — One TRM per concrete container shape, plus a fallback trap

Arrays and openArrays are not the same shape for pattern matching.
`plugins/osproc.nim` emits TRMs for `seq[string]`, `array[0, string]`
through `array[8, string]`, AND a fallback `openArray[string]` trap
that raises `UnmockableContainerDefect` so a caller using `toOpenArray`
can't silently escape the mock.

## Rule 4 — Use `{.noRewrite.}:` statement-blocks for spy passthrough

Inside a TRM body, if you need to call the original proc (spy mode,
or the plugin passes through unmocked calls), wrap the real call in
`{.noRewrite.}:`. Without this, the TRM re-enters itself infinitely.

## Rule 5 — Construct Futures via `tripwire/futures`, not inline `complete`

Chronos 4.x has a lexical-scoping issue where `complete(fut, value)`
inside a TRM template body crashes the Nim compiler (the macro engine
loses track of the `Future[T]` type binding when `complete` is invoked
in template-expansion context). Delegate to `makeCompletedFuture` from
`tripwire/futures.nim`, which wraps the complete call in a runtime proc
that the macro engine handles cleanly.

## Rule 6 — The TRM body calls `tripwireCountRewrite()` first

The per-TU rewrite cap (~15 rewrites per translation unit, enforced
by `cap_counter.nim`) catches runaway TRM expansions before they blow
out compile times. The `tripwireInterceptBody` and
`tripwirePluginIntercept` combinators handle this for you. If you
write a custom body, call `tripwireCountRewrite()` as the first
statement.

## Rule 7 — Every TRM body checks the current verifier

`tripwireInterceptBody` does this: if `currentVerifier()` is nil, raise
`LeakedInteractionDefect`. If the verifier is popped but still current
(generation mismatch), raise `PostTestInteractionDefect`. Hand-rolled
TRM bodies MUST replicate these checks; `test_intercept.nim` enforces
them.

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
`tuple[output: string, exitCode: int]`; the TRM must use that
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

## Rule 14 — Firewall-only plugins are a valid pattern when the target library has private response state

Some libraries cannot be fully mocked from outside without forbidden
idioms (`cast`, `unsafeNew`). Chronos's `HttpClientResponse` is the
canonical example: its `state` field is private (`apps/http/httpclient
.nim:167` in the chronos tree) with no public constructor. A full mock
plugin would have to fabricate a synthetic response; that requires
reaching into private fields, which clean-room plugins MUST NOT do.

**The way out: don't try to mock; firewall instead.** A firewall-only
plugin enforces Guarantee 1 (every external call is pre-authorized)
without ever constructing a response object. The TRM body either:

- raises `UnmockedInteractionDefect` when no `allow`/`restrict` rule
  matches, or
- calls through to the real proc (passthrough).

No synthetic-response construction. The private-field wall doesn't
matter because the plugin is the gatekeeper, not a substitute.

`plugins/chronos_httpclient.nim` and `plugins/websock.nim` are the
reference implementations. The TRM bodies use `tripwirePluginIntercept`
exactly like a full mock plugin would, but the `MockResponse` subtypes'
`realize` method bodies raise a Defect: registering a mock against a
firewall-only plugin is unsupported, and the realize path is
unreachable in normal use. Consumers continue to mock at their own DI
seams (closures, factories) for G2/G3 coverage.

When to choose firewall-only:

- The target library has private fields that block synthetic-response
  construction without `cast` / `unsafeNew`.
- The library is only used inside a higher-level abstraction the
  consumer already mocks via DI (so G2/G3 is covered there).
- G1 alone is sufficient: you want unmocked calls to fail loudly, but
  you don't need to feed back canned responses.

When to choose a full mock plugin instead:

- The target library has either fully-public response types or a
  cooperatively-exported test seam (e.g., `mockNew` constructors).
- The consumer needs deterministic per-call response control without
  routing through their own DI seam.

The empirical investigation behind this rule (three strategies tried
against chronos: synthetic-response construction, dispatcher
substitution, and finally firewall-only) ruled out the first two on
the private-field constraint and on chronos dispatcher ownership
respectively. Firewall-only was the only shape that fit the
clean-room requirement.

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
see the `mockable`/`expect`/`assert` macros in `plugins/mock.nim`; the
same pattern generalizes to any plugin that accepts value-typed args.

## Further reading

- `src/tripwire/plugins/plugin_intercept.nim` — the combinator plugin
  TRMs are expected to wrap their bodies in.
- `src/tripwire/plugins/mock.nim` — the only built-in that supports
  outside-sandbox passthrough; reference for the `supportsPassthrough`
  override.
- `src/tripwire/plugins/httpclient.nim` — full-mock reference for
  multisync (Rule 9), default-value reproduction (Rule 1), and the
  wrapper canonicalization DSL (Rule 13).
- `src/tripwire/plugins/osproc.nim` — full-mock reference for
  fixed-arity container TRMs and the `openArray` fallback trap
  (Rule 3), anonymous tuple returns (Rule 10), and `tripwireRaw*`
  spy helpers (Rule 11).
- `src/tripwire/plugins/chronos_httpclient.nim` and `plugins/websock.nim`
  — firewall-only references (Rule 14).
- `src/tripwire/cap_counter.nim` — the per-TU rewrite cap referenced
  in Rule 6.
- [`docs/quickstart.md`](quickstart.md) — install, activate, first
  test, firewall API.
- [`docs/roadmap-v0.3.md`](roadmap-v0.3.md) — what v0 deliberately
  does not ship, including item 6 (plugin TRM auto-installation) and
  item 14 (additional stdlib and third-party plugins).
