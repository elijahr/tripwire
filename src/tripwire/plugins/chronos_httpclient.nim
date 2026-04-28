## tripwire/plugins/chronos_httpclient.nim — chronos httpclient firewall.
##
## **Firewall-only plugin** — Guarantee #1 (every external call is
## pre-authorized). G2 (every recorded interaction is asserted) and
## G3 (every registered mock is consumed) are NOT enforced for
## chronos httpclient. Mocking is unsupported.
##
## ## Why firewall-only
##
## Strategy A — full mock-style interception that constructs a synthetic
## `HttpClientResponseRef` to feed back to the caller — was investigated
## and ruled INFEASIBLE without forbidden idioms (`cast`, `unsafeNew`).
## See `docs/journal/2026-04-25-tripwire-chronos-plugin-pivot.md` in the
## paperplanes worktree for the full investigation.
##
## The wall: `chronos.HttpClientResponse.state` is a private field
## (`apps/http/httpclient.nim:167`). There is no public constructor and
## no public way to set the field from another module. Constructing a
## working response from outside chronos requires either `cast[T]` or
## `unsafeNew`, both of which violate paperplanes' forbidden-idiom CI.
##
## **Firewall-only sidesteps the wall.** The TRM body never constructs
## a response. It either:
##
##   * raises `UnmockedInteractionDefect` when no `allow`/`restrict` rule
##     matches, OR
##   * passes through to the real chronos proc (the plugin is the
##     gatekeeper, not a substitute).
##
## So the private-`state` issue never enters the picture — we don't build
## a response, we just decide whether the call is allowed to make one.
##
## ## What this plugin gives consumers
##
## paperplanes (and other consumers) get **G1 coverage on chronos HTTP**:
## an unauthorized chronos httpclient call inside a tripwire `sandbox:`
## block raises `UnmockedInteractionDefect` instead of silently hitting
## the network. Consumers route mocked HTTP responses through their own
## DI seams (paperplanes uses `HttpSender` / `HttpPostFn` closures).
##
## ## Surfaces intercepted
##
##   * `send(request: HttpClientRequestRef)` — line 1181 in chronos
##     `httpclient.nim`. THE actual network point. paperplanes' real
##     POST path goes `HttpClientRequestRef.post(...)` (no network) →
##     `req.send()` (network) → `resp.getBodyBytes()` (more network).
##     Intercepting `send` covers the network boundary; the body-read
##     happens against an already-allowed connection.
##   * `fetch(session: HttpSessionRef, url: Uri)` — line 1521. Convenience
##     GET. Intercepted as a separate firewall surface so callers using
##     the URL-only convenience get the same G1 protection.
##   * `fetch(request: HttpClientRequestRef)` — line 1504. Request-form
##     convenience that returns `(status, body)`. Intercepted as a
##     separate firewall surface. The earlier assumption that the
##     existing `send` TRM would transitively cover this code path was
##     wrong: chronos's `fetch(req)` body compiles outside the
##     tripwire-active compilation unit, so the inner `request.send()`
##     call inside chronos is NOT subject to TRM rewriting. Without an
##     explicit TRM here, `req.fetch()` reached the network with no
##     firewall consultation. G1 now holds on both fetch shapes.

import std/[uri, options]
import chronos
import chronos/apps/http/httpclient
import chronos/apps/http/httpcommon
import ../[types, registry, timeline, sandbox, verify, intercept]
import ./plugin_intercept

export plugin_intercept.tripwirePluginIntercept

type
  ChronosHttpPlugin* = ref object of Plugin

  ChronosHttpSendStubResponse* = ref object of MockResponse
    ## Stub MockResponse for the `send` TRM. The combinator's `respType`
    ## parameter requires SOME MockResponse subclass whose `realize` returns
    ## the TRM's declared return type; we use this stub but never populate
    ## it from a `registerMock` site (firewall-only mode does not support
    ## mock registration). If a consumer somehow does register a mock
    ## against this plugin, `realize` raises a descriptive Defect rather
    ## than returning bogus data.
    discard

  ChronosHttpFetchStubResponse* = ref object of MockResponse
    ## Sibling stub for the `fetch(session, url)` TRM. Separate type
    ## because its `realize` return type differs from the `send` stub's
    ## (`Future[HttpResponseTuple]` vs `Future[HttpClientResponseRef]`)
    ## and Nim methods dispatch on subtype, not on the return type alone.
    discard

const FirewallOnlyMockMsg =
  "tripwire/plugins/chronos_httpclient is firewall-only; " &
  "mock registration is unsupported. Use closure-based DI (e.g. " &
  "paperplanes' HttpSender / HttpPostFn) for G2/G3 coverage."

method realize*(r: ChronosHttpSendStubResponse):
    InternalRaisesFuture[HttpClientResponseRef,
                         (CancelledError, HttpError)] {.
      base, gcsafe, raises: [Defect].} =
  ## Mocking unsupported — see module docstring. The combinator only
  ## reaches this branch if a consumer registered a mock against this
  ## plugin, which the firewall-only design forbids. Return type
  ## matches the corresponding TRM's chronos-`async:` shape (see the
  ## TRM-block comments below for why `InternalRaisesFuture` rather
  ## than plain `Future`).
  ##
  ## `raises: [Defect]` is load-bearing — see `MockResponse.realize`
  ## docstring in `tripwire/intercept.nim` for the rationale. Without
  ## this annotation, Nim infers the maximum (Exception) and the TRM
  ## expansion fails to type-check inside chronos `async: (raises: [...])`
  ## consumer procs.
  raise newException(Defect, FirewallOnlyMockMsg)

method realize*(r: ChronosHttpFetchStubResponse):
    InternalRaisesFuture[HttpResponseTuple,
                         (CancelledError, HttpError)] {.
      base, gcsafe, raises: [Defect].} =
  ## See `ChronosHttpSendStubResponse.realize` docstring for the
  ## `raises: [Defect]` rationale.
  raise newException(Defect, FirewallOnlyMockMsg)

let chronosHttpPluginInstance* = ChronosHttpPlugin(name: "chronos_httpclient",
                                                   enabled: true)
registerPlugin(chronosHttpPluginInstance)

# ---- Fingerprinting ------------------------------------------------------

proc bracketIfV6(host: string): string {.inline.} =
  ## Re-bracket IPv6 hostnames so the host token stays a single
  ## whitespace-delimited unit (matches the convention in
  ## `plugins/httpclient.fingerprintHttpRequest`).
  if host.len > 0 and ':' in host: "[" & host & "]" else: host

proc fingerprintChronosSend*(meth: HttpMethod, addr0: HttpAddress): string =
  ## Canonicalize a `send(request)` call to a stable typed-token
  ## fingerprint string.
  ##
  ## Format:
  ##   `procName=send method=<METHOD> scheme=<scheme> host=<host>
  ##    port=<port> path=<path> query=<query>`
  ##
  ## Matches the `key=value` shape that
  ## `sandbox.matchesFingerprint` anchors against, so M(host=...) /
  ## M(port=...) / M(scheme=...) / M(httpMethod=...) / M(path=...)
  ## filter precisely on the corresponding token's value rather than
  ## any whitespace-delimited substring. `query=` is included so two
  ## sends to the same path with different query strings produce
  ## distinct fingerprints (Guarantee 1 / 2 interaction-uniqueness).
  let scheme =
    case addr0.scheme
    of HttpClientScheme.NonSecure: "http"
    of HttpClientScheme.Secure: "https"
  "procName=send method=" & $meth & " scheme=" & scheme &
    " host=" & bracketIfV6(addr0.hostname) & " port=" & $addr0.port &
    " path=" & escapeFingerprintField(addr0.path) &
    " query=" & escapeFingerprintField(addr0.query)

proc fingerprintChronosFetchReq*(meth: HttpMethod, addr0: HttpAddress): string =
  ## Canonicalize a `fetch(request)` call. Mirrors `fingerprintChronosSend`
  ## but with `procName=fetch` so the matcher DSL can distinguish the
  ## two surfaces if needed. The request's method may be any HTTP verb
  ## — chronos `fetch(req)` doesn't coerce GET.
  let scheme =
    case addr0.scheme
    of HttpClientScheme.NonSecure: "http"
    of HttpClientScheme.Secure: "https"
  "procName=fetch method=" & $meth & " scheme=" & scheme &
    " host=" & bracketIfV6(addr0.hostname) & " port=" & $addr0.port &
    " path=" & escapeFingerprintField(addr0.path) &
    " query=" & escapeFingerprintField(addr0.query)

proc fingerprintChronosFetch*(url: Uri): string =
  ## Canonicalize a `fetch(session, url)` call. Always GET (chronos's
  ## URL-only fetch hardcodes GET). Same typed-token shape as
  ## `fingerprintChronosSend` so matchers apply uniformly.
  ##
  ## Default ports filled in (80 for http, 443 for https) so
  ## `M(port=80)` works against `http://host/path` URIs that omit the
  ## port. `query=` is included so two fetches to the same path with
  ## different query strings produce distinct fingerprints (G1 / G2
  ## interaction-uniqueness). Redirects happen under the hood via
  ## `request.redirect()` which builds a new request and `send`s it;
  ## that inner `send` is intercepted by `sendTRM` separately, so each
  ## redirect hop is firewall-checked.
  var port = url.port
  if port.len == 0:
    port = (if url.scheme == "https": "443" else: "80")
  "procName=fetch method=GET scheme=" & url.scheme &
    " host=" & bracketIfV6(url.hostname) & " port=" & port &
    " path=" & escapeFingerprintField(url.path) &
    " query=" & escapeFingerprintField(url.query)

# ---- Real-proc trampolines (avoid TRM self-recursion) -------------------
# Following the precedent established in `plugins/osproc.nim`
# (`realExecCmdEx`, commit `0c9dc2b`). Nim 2.2.8's TRM rewriter under
# certain {.dirty.} expansion paths fails to honor a `{.noRewrite.}:`
# block on the spy-passthrough call: the inner `send(req)` re-matches
# the enclosing `sendTRM`, producing unbounded expansion that trips the
# 15-rewrite cap counter. Routing through a RENAMED proc makes the call
# site a non-`send` symbol so the TRM pattern matcher cannot match it.
#
# These are real procs (not procvars) because chronos's `async:` pragma
# attaches a non-portable `InternalRaisesFuture` shape to the proc value
# that doesn't round-trip through a generic `proc(...)` typed `let`
# binding. A thin wrapper proc body (which calls the underlying chronos
# proc directly) is the simplest shape that compiles cleanly under
# 2.2.8 + chronos 4.2.
#
# `{.noRewrite.}` pragmas on the inner calls are belt-and-braces against
# any future TRM that might still try to match across the rename
# boundary. Both procs are exported because `tripwirePluginIntercept` is
# {.dirty.} and inlines its `spyBody` (which references these symbols)
# at every consumer call site; the symbols must be reachable from those
# sites.

proc realChronosSend*(request: HttpClientRequestRef):
                       Future[HttpClientResponseRef] {.
                         async: (raises: [CancelledError, HttpError]).} =
  ## Trampoline to chronos's real `send`. The outer name differs from
  ## `send` so the TRM pattern matcher can't see this call site.
  {.noRewrite.}:
    return await httpclient.send(request)

proc realChronosFetchUri*(session: HttpSessionRef, url: Uri):
                           Future[HttpResponseTuple] {.
                             async: (raises: [CancelledError, HttpError]).} =
  ## Trampoline to chronos's real URL-only `fetch`.
  {.noRewrite.}:
    return await httpclient.fetch(session, url)

proc realChronosFetchReq*(request: HttpClientRequestRef):
                           Future[HttpResponseTuple] {.
                             async: (raises: [CancelledError, HttpError]).} =
  ## Trampoline to chronos's real request-form `fetch`. The outer name
  ## differs from `fetch` so the TRM pattern matcher can't see this
  ## call site, mirroring the rename pattern used by `realChronosSend`.
  {.noRewrite.}:
    return await httpclient.fetch(request)

# ---- TRMs ----------------------------------------------------------------
#
# ## On the `InternalRaisesFuture` return type
#
# Chronos's `async: (raises: [E1, E2])` pragma rewrites a proc whose
# DECLARED return type is `Future[T]` into one whose IMPLEMENTED return
# type is `InternalRaisesFuture[T, (E1, E2)]` (a subtype of `Future[T]`
# carrying the raises list at the type level for compile-time effect
# tracking). Nim's TRM pattern matcher matches on the IMPLEMENTED shape
# that callers actually see, so the TRM's declared return type must be
# the `InternalRaisesFuture[T, (raises tuple)]` form. Declaring just
# `Future[T]` produces an "expected `InternalRaisesFuture[...]` got
# `Future[...]`" mismatch at the call site — the rewriter substitutes
# the TRM body's return type, and the surrounding code expects the
# subtype.
#
# The raises tuple `(CancelledError, HttpError)` mirrors the real
# chronos signature exactly. Any drift here will silently break
# interception (the TRM declares one shape; the rewriter looks for a
# different shape; no rewrite happens; the call hits chronos directly).
# A future chronos release that adds another raised type to `send` /
# `fetch` MUST be paired with an update to these TRMs and to
# `realChronosSend` / `realChronosFetchUri` above.

template chronosSendTRM*{send(request)}(
    request: HttpClientRequestRef):
    InternalRaisesFuture[HttpClientResponseRef,
                         (CancelledError, HttpError)] =
  ## Firewall TRM for `chronos.httpclient.send`. The TRM body either
  ## raises `UnmockedInteractionDefect` (when the firewall says no) or
  ## calls through to the real `httpclient.send` via `realChronosSend`
  ## (when an `allow`/`restrict` rule matches). No synthetic-response
  ## construction; no mocking.
  ##
  ## Pattern variable: `request: HttpClientRequestRef`. Return type
  ## matches chronos's expanded `async:` shape (see the comment block
  ## above this template).
  tripwirePluginIntercept(
    chronosHttpPluginInstance,
    "send",
    fingerprintChronosSend(request.meth, request.address),
    ChronosHttpSendStubResponse):
    {.noRewrite.}:
      realChronosSend(request)

template chronosFetchUriTRM*{fetch(session, url)}(
    session: HttpSessionRef, url: Uri):
    InternalRaisesFuture[HttpResponseTuple,
                         (CancelledError, HttpError)] =
  ## Firewall TRM for `chronos.httpclient.fetch(session, url)` — the
  ## URL-only convenience GET. Same firewall-only semantics as
  ## `chronosSendTRM`. Return type matches chronos's expanded `async:`
  ## shape.
  tripwirePluginIntercept(
    chronosHttpPluginInstance,
    "fetch",
    fingerprintChronosFetch(url),
    ChronosHttpFetchStubResponse):
    {.noRewrite.}:
      realChronosFetchUri(session, url)

template chronosFetchReqTRM*{fetch(request)}(
    request: HttpClientRequestRef):
    InternalRaisesFuture[HttpResponseTuple,
                         (CancelledError, HttpError)] =
  ## Firewall TRM for `chronos.httpclient.fetch(request)` — the
  ## request-form convenience that returns `(status, body)`. Mirrors
  ## `chronosFetchUriTRM` exactly modulo the pattern (`fetch(request)`
  ## vs `fetch(session, url)`), the fingerprint helper, and the
  ## trampoline. Same firewall-only semantics as `chronosSendTRM`.
  ##
  ## This TRM closes a silent G1 bypass: chronos's `fetch(req)` body
  ## internally calls `request.send()`, but that inner call compiles
  ## inside chronos (outside the tripwire-active compilation unit) so
  ## the existing `chronosSendTRM` is NOT applied. Without this TRM,
  ## `req.fetch()` reached the network with no firewall consultation.
  ##
  ## The raises tuple `(CancelledError, HttpError)` matches chronos's
  ## actual `fetch(request)` signature at `httpclient.nim:1505`.
  tripwirePluginIntercept(
    chronosHttpPluginInstance,
    "fetch",
    fingerprintChronosFetchReq(request.meth, request.address),
    ChronosHttpFetchStubResponse):
    {.noRewrite.}:
      realChronosFetchReq(request)
