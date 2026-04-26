## tripwire/plugins/websock.nim — websock client firewall.
##
## **Firewall-only plugin** — Guarantee #1 (every external call is
## pre-authorized). G2 (every recorded interaction is asserted) and
## G3 (every registered mock is consumed) are NOT enforced for
## websock. Mocking is unsupported.
##
## ## Why firewall-only
##
## Strategy A — full mock-style interception that constructs a synthetic
## `WSSession` to feed back to the caller — is technically possible
## without forbidden idioms (every `WSSession` field is `*` (public) per
## `websock/types.nim`), but synthesising a usable session requires a
## working `chronos.AsyncStream` (with reader/writer pair driven from a
## byte-level frame decoder buffer). That is effectively a re-implementation
## of half of websock's IO stack inside tripwire — high cost, high risk,
## low marginal value over the simple firewall path.
##
## Strategy D (firewall-only) sidesteps the cost. The TRM body never
## constructs a `WSSession`. It either:
##
##   * raises `UnmockedInteractionDefect` when no `allow`/`restrict` rule
##     matches, OR
##   * passes through to the real `WebSocket.connect` (the plugin is the
##     gatekeeper, not a substitute).
##
## So the question of "synthesise an `AsyncStream`?" never enters the
## picture — we don't build a session, we just decide whether the call
## is allowed to make one.
##
## ## What this plugin gives consumers
##
## paperplanes (and other consumers) get **G1 coverage on websock** by
## calling `nfwebsockConnect(uri)` instead of `WebSocket.connect(uri)`
## directly. Inside a tripwire `sandbox:` block, an unauthorised
## `nfwebsockConnect` call raises `UnmockedInteractionDefect` instead of
## silently hitting the network. Consumers route mocked WS traffic
## through their own DI seams (paperplanes uses a `WsTransport` base
## class with `RealWsTransport` and `FakeWsTransport` subclasses);
## `RealWsTransport` is the only call site for `nfwebsockConnect` in
## the project today.
##
## ## Why a free-function wrapper instead of intercepting `WebSocket.connect`
##
## Nim 2.2.8's TRM pattern matcher does NOT match call shapes whose
## receiver is a `typedesc`. Empirically verified across four pattern
## variants — fully qualified, post-method-call, typedesc-as-bound-var,
## and dotted-typedesc — none fire at the `WebSocket.connect(uri)` call
## site. Other tripwire TRMs (chronos httpclient `send`/`fetch`, osproc
## `execProcess`) targeting non-typedesc receivers fire correctly; the
## limitation is specific to typedesc receivers.
##
## Workaround: the plugin exposes a free-function wrapper
## `nfwebsockConnect(uri)`. The TRM matches the wrapper by name. The
## wrapper delegates to `WebSocket.connect(uri)` only when the firewall
## admits the call. **Direct `WebSocket.connect(uri)` calls bypass
## tripwire by design** and are a grep-detectable forbidden idiom in
## consumer repositories.
##
## ## Surfaces intercepted
##
##   * `nfwebsockConnect(uri: Uri)` — drop-in wrapper for
##     `WebSocket.connect(uri, ...)` (line 198 of `websock/websock.nim`).
##     THE network boundary on the client side. Once the connect is
##     `allow`'d, all subsequent `send` / `recvMsg` / `close` calls ride
##     the same authorised connection.
##
## Not intercepted (deliberate):
##
##   * `WebSocket.connect(host, path, ...)` — the host/path overload at
##     line 90. paperplanes always goes through the `Uri` overload; if a
##     future consumer needs the host/path form, mirror `nfwebsockConnect`
##     with the host/path signature.
##   * `WSSession.send` / `recvMsg` / `close` / `ping` — post-handshake
##     wire ops. After the connect is allowed, these ride the same
##     already-authorised connection. Adding TRMs here would double-fire
##     on every sent frame (a single round-trip would record dozens of
##     entries), bloating timelines for no firewall benefit.
##   * `WSServer.handleRequest` — server-side accept. paperplanes' tests
##     CALL this from their server fixtures, not the production code;
##     paperplanes runtime is a WS client, never a WS server.
##     Intercepting `handleRequest` would force test fixtures to
##     allow-list themselves, adding noise.
##
## ## Hazards (carried over from chronos plugin)
##
##   * `async: (raises: [...])` rewrites `Future[T]` to
##     `InternalRaisesFuture[T, (raises tuple)]` at the call site. The
##     TRM's declared return type must match the rewritten shape, not
##     plain `Future[WSSession]`. The connect URI overload's raises list
##     is `(CancelledError, AsyncStreamError, HttpError, TransportError,
##     WebSocketError)`.
##   * TRM self-recursion under Nim 2.2.8 + chronos: spy-passthrough
##     goes through a renamed trampoline (`realWebsockConnectUri`).
##     The rename moves the inner call site to a non-`connect` symbol
##     so the TRM pattern matcher cannot re-match it.
##   * `{.raises: [Defect].}` on the stub `MockResponse.realize`. Without
##     this annotation, Nim infers the maximum (`Exception`) and the TRM
##     expansion fails to type-check inside chronos
##     `async: (raises: [...])` consumer procs (the `74d540a` lesson).

import std/[uri, options]
import chronicles
  # Imported because websock's internal `connect` body invokes
  # `chronicles.trace(...)` via its `logScope`. The trampoline's
  # `await wsLib.WebSocket.connect(uri)` body, when expanded under
  # `async:`, types `setResult` against websock internals that reach
  # for `activeChroniclesStream` from the importer's scope. Without
  # this `import` here, compilation fails with
  #   "undeclared identifier: 'activeChroniclesStream'"
  # at websock's `client.nim` `trace` site.
import chronos
import chronos/transports/common as chronosCommon
import websock/websock
import websock/types as wsTypes
import websock/http/common as wsHttpCommon
import ../[types, registry, timeline, sandbox, verify, intercept]
import ./plugin_intercept

export plugin_intercept.tripwirePluginIntercept

type
  WebsockPlugin* = ref object of Plugin

  WebsockConnectStubResponse* = ref object of MockResponse
    ## Stub MockResponse for the `WebSocket.connect(uri)` TRM. The
    ## combinator's `respType` parameter requires SOME MockResponse
    ## subclass whose `realize` returns the TRM's declared return type;
    ## we use this stub but never populate it from a `registerMock` site
    ## (firewall-only mode does not support mock registration). If a
    ## consumer somehow does register a mock against this plugin,
    ## `realize` raises a descriptive Defect rather than returning bogus
    ## data.
    discard

const FirewallOnlyMockMsg =
  "tripwire/plugins/websock is firewall-only; " &
  "mock registration is unsupported. Use closure-based DI (e.g. " &
  "paperplanes' WsTransport / RealWsTransport / FakeWsTransport) for " &
  "G2/G3 coverage."

method realize*(r: WebsockConnectStubResponse):
    InternalRaisesFuture[WSSession,
                         (CancelledError, AsyncStreamError,
                          wsHttpCommon.HttpError, TransportError,
                          WebSocketError)] {.
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

let websockPluginInstance* = WebsockPlugin(name: "websock", enabled: true)
registerPlugin(websockPluginInstance)

# ---- Fingerprinting ------------------------------------------------------

proc fingerprintWebsockConnect*(uri: Uri): string =
  ## Canonicalize a `WebSocket.connect(uri)` call to a stable fingerprint
  ## string. Includes scheme + hostname + port + path so the matcher DSL
  ## can pattern-match by host / port / path / scheme against it.
  ##
  ## Format: `"connect <SCHEME>://<HOST>:<PORT><PATH>"`. Matches the
  ## fingerprint shape `sandbox.matchesFingerprint` expects (host
  ## substring or glob match; `:<port>` substring; scheme substring).
  ##
  ## Default ports are filled in (80 for ws, 443 for wss) so a matcher
  ## using `M(port = 80)` works against `ws://host/path` URIs that
  ## omit the port.
  var port = uri.port
  if port.len == 0:
    port = (if uri.scheme == "wss": "443" else: "80")
  "connect " & uri.scheme & "://" & uri.hostname & ":" & port & uri.path

# ---- Real-proc trampolines (avoid TRM self-recursion) -------------------
# Following the precedent established in `plugins/osproc.nim`
# (`realExecCmdEx`, commit `0c9dc2b`) and reinforced by
# `plugins/chronos_httpclient.nim` (`realChronosSend`, commit `4f94087`).
# Nim 2.2.8's TRM rewriter under certain {.dirty.} expansion paths fails
# to honor a `{.noRewrite.}:` block on the spy-passthrough call: the
# inner `connect(WebSocket, uri)` re-matches the enclosing TRM,
# producing unbounded expansion that trips the 15-rewrite cap counter.
# Routing through a RENAMED proc makes the call site a non-`connect`
# symbol so the TRM pattern matcher cannot match it.
#
# This is a real proc (not a procvar) because chronos's `async:` pragma
# attaches a non-portable `InternalRaisesFuture` shape to the proc value
# that doesn't round-trip through a generic `proc(...)` typed `let`
# binding. A thin wrapper proc body (which calls the underlying websock
# proc directly) is the simplest shape that compiles cleanly under
# 2.2.8 + websock 0.3.0 + chronos 4.2.
#
# `{.noRewrite.}` on the inner call is belt-and-braces against any
# future TRM that might still try to match across the rename boundary.
# Exported because `tripwirePluginIntercept` is {.dirty.} and inlines
# its `spyBody` (which references this symbol) at every consumer call
# site; the symbol must be reachable from those sites.

proc realWebsockConnectUri*(uri: Uri):
                             Future[WSSession] {.
                               async: (raises: [CancelledError, AsyncStreamError,
                                                wsHttpCommon.HttpError, TransportError,
                                                WebSocketError]).} =
  ## Trampoline to websock's real URI-form `connect`. Used by the TRM's
  ## spy-passthrough body when the firewall admits a call. The outer name
  ## differs from `connect` and from `nfwebsockConnect` so the TRM
  ## pattern matcher cannot re-match it (avoids unbounded TRM
  ## self-recursion under Nim 2.2.8 + chronos `async:`).
  {.noRewrite.}:
    return await WebSocket.connect(uri)

# ---- Public consumer entrypoint -----------------------------------------
#
# ## Why a wrapper proc instead of intercepting `WebSocket.connect` directly
#
# Nim 2.2.8's term-rewriting macro engine does NOT match patterns whose
# call shape includes a `typedesc` receiver. Empirically verified across
# four pattern variants:
#
#   * `{wsLib.WebSocket.connect(uri)}` — fully qualified
#   * `{connect(WebSocket, uri)}` — post-method-call AST shape
#   * `{connect(t, uri)}` with `t: typedesc[WebSocket]` — bound typedesc var
#   * `{x.connect(uri)}` with `x: typedesc[WebSocket]` — dotted form
#
# None of these patterns fire at the call site `WebSocket.connect(uri)`.
# The TRM declares cleanly (no compile error), but the rewriter never
# matches. (Other tripwire TRMs targeting non-typedesc receivers — see
# `chronos_httpclient.send`, `chronos_httpclient.fetch`, `osproc.execProcess`
# — fire correctly; the failure is specific to typedesc receivers.)
#
# Workaround: intercept a free-function wrapper instead. Consumers call
# `nfwebsockConnect(uri)`, which the TRM matches by name. The wrapper
# delegates to `WebSocket.connect(uri)` only when the firewall admits.
# Direct `WebSocket.connect(uri)` calls bypass tripwire by design — that
# is documented and grep-detectable as a forbidden idiom in consumer
# repositories.

proc nfwebsockConnect*(uri: Uri):
                       Future[WSSession] {.
                         async: (raises: [CancelledError, AsyncStreamError,
                                          wsHttpCommon.HttpError, TransportError,
                                          WebSocketError]).} =
  ## Firewall-protected entrypoint for websock URI-form connect. Drop-in
  ## replacement for `WebSocket.connect(uri)`. Inside a tripwire `sandbox:`
  ## block, an unauthorised call raises `UnmockedInteractionDefect`. The
  ## TRM `nfwebsockConnectTRM` (below) intercepts callers of this proc.
  ##
  ## The body forwards to the real websock proc unconditionally; the TRM
  ## rewrites callers so this body is only reached as the spy-passthrough
  ## branch (i.e., the firewall already approved the call).
  {.noRewrite.}:
    return await WebSocket.connect(uri)

# ---- TRMs ----------------------------------------------------------------
#
# ## On the `InternalRaisesFuture` return type
#
# Chronos's `async: (raises: [E1, E2, ...])` pragma rewrites a proc whose
# DECLARED return type is `Future[T]` into one whose IMPLEMENTED return
# type is `InternalRaisesFuture[T, (E1, E2, ...)]` (a subtype of
# `Future[T]` carrying the raises list at the type level for compile-time
# effect tracking). Nim's TRM pattern matcher matches on the IMPLEMENTED
# shape that callers actually see, so the TRM's declared return type must
# spell `InternalRaisesFuture[WSSession, (raises tuple)]`. Declaring just
# `Future[WSSession]` produces an "expected `InternalRaisesFuture[...]`
# got `Future[...]`" mismatch at the call site — the rewriter substitutes
# the TRM body's return type, and the surrounding code expects the
# subtype.
#
# The raises tuple `(CancelledError, AsyncStreamError, HttpError,
# TransportError, WebSocketError)` mirrors websock's URI-form `connect`
# signature exactly (`websock/websock.nim:198-216`). Any drift here will
# silently break interception (the TRM declares one shape; the rewriter
# looks for a different shape; no rewrite happens; the call hits the
# wrapper directly).

template nfwebsockConnectTRM*{nfwebsockConnect(uri)}(
    uri: Uri):
    InternalRaisesFuture[WSSession,
                         (CancelledError, AsyncStreamError,
                          wsHttpCommon.HttpError, TransportError,
                          WebSocketError)] =
  ## Firewall TRM for `nfwebsockConnect(uri)`. The TRM body either raises
  ## `UnmockedInteractionDefect` (when the firewall says no) or calls
  ## through to the real `WebSocket.connect(uri)` via
  ## `realWebsockConnectUri` (when an `allow`/`restrict` rule matches).
  ## No synthetic-response construction; no mocking.
  tripwirePluginIntercept(
    websockPluginInstance,
    "connect",
    fingerprintWebsockConnect(uri),
    WebsockConnectStubResponse):
    {.noRewrite.}:
      realWebsockConnectUri(uri)
