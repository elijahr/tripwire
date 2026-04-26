## tests/test_websock_firewall.nim — websock client firewall-only
## plugin behavioral tests (G1 enforcement, allow/restrict interaction,
## fmWarn lane).
##
## Gated at module scope by `when defined(websock) and defined(chronos)`
## so the file is a no-op when compiled without the relevant defines.
## The standalone websock cell (`TRIPWIRE_TEST_WEBSOCK=1` →
## cell #6d in tripwire.nimble) exercises it; default cells skip
## silently.
##
## ## Why this file is its own standalone cell
##
## The websock firewall plugin emits one TRM (`nfwebsockConnect(uri)`)
## that counts toward Defense 3's 15-rewrites-per-compilation-unit cap
## (`cap_counter.nim`). Combined with this file's per-test wrappers
## and the chronos aggregate's TRM rewrites, co-locating risks going
## over. Following the precedent set by `test_osproc_arrays.nim`,
## `test_firewall.nim`, and `test_chronos_httpclient_firewall.nim`,
## this file lives in its own cell.
##
## ## Why the tests call `nfwebsockConnect(uri)` not `WebSocket.connect(uri)`
##
## Nim 2.2.8 TRMs do not match patterns whose call shape includes a
## `typedesc` receiver (verified empirically: `{WebSocket.connect(uri)}`,
## `{connect(WebSocket, uri)}`, and `{x.connect(uri)}` with a typedesc
## bound variable all fail to match). The websock plugin works around
## this by exposing a free-function wrapper `nfwebsockConnect(uri)` and
## intercepting THAT name. Consumers (paperplanes' RealWsTransport) call
## the wrapper instead of `WebSocket.connect` directly. Direct
## `WebSocket.connect` calls bypass tripwire BY DESIGN and are a
## grep-detectable forbidden idiom in consumer repositories.
when defined(websock) and defined(chronos):
  import std/[unittest, uri]
  import chronicles
    # Required: websock's internal handlers emit `chronicles.trace`
    # calls via `logScope`. Without `chronicles` in the test module's
    # scope, `HttpServer.create(...)` and `nfwebsockConnect(...)`
    # expansions fail with `undeclared identifier:
    # 'activeChroniclesStream'` (websock looks up the symbol in the
    # caller's scope).
  import chronos
  import chronos/transports/common as chronosCommon
  import websock/websock
  import websock/types as wsTypes
  import websock/http/server as wsServer
  import websock/http/common as wsHttpCommon
  import tripwire/[types, errors, sandbox, verify, timeline]
  import tripwire/plugins/websock as nfwebsock

  # ------------------------------------------------------------------
  # Test fixtures
  # ------------------------------------------------------------------

  # A never-bound IP+port so a firewall miss raises before any real
  # network round-trip can hang the test. RFC 5737 documentation prefix
  # 192.0.2.0/24 routes nowhere; a connection attempt fails immediately
  # on most stacks. Port 1 (privileged, never listening) gives an extra
  # signal in case the test harness disagrees about routability.
  const NeverBoundUrl = "ws://192.0.2.1:1/never"

  type
    TestWsServer = ref object
      ## One server per test. `port` is the OS-assigned ephemeral port
      ## resolved after `start()`. Minimal handler — accepts the
      ## upgrade, sends a sentinel frame, closes. The plugin tests do
      ## not need request/response shaping beyond that; they exercise
      ## the firewall, not websock's IO.
      httpServer: HttpServer
      port: int

  proc helloHandler(request: HttpRequest) {.async.} =
    ## Minimal upgrade-then-close handler. The connect-side firewall
    ## is what we're testing; the server only needs to complete the
    ## handshake so that `WebSocket.connect(uri)` returns OK.
    let ws = WSServer.new(protos = ["", "tripwire-test"])
    var session: WSSession
    try:
      session = await ws.handleRequest(request)
    except CancelledError as exc:
      raise exc
    except CatchableError:
      return
    try:
      await session.send("hello-from-tripwire-test")
      await session.close()
    except CancelledError as exc:
      raise exc
    except CatchableError:
      discard

  proc startTestWsServer(): TestWsServer =
    ## Bind `127.0.0.1:0`, register the handler, resolve the ephemeral
    ## port. Panics on bind failure — a test fixture doesn't gracefully
    ## degrade.
    let ts = TestWsServer()
    let flags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr}
    let addr0 = initTAddress("127.0.0.1:0")
    let server = HttpServer.create(addr0, helloHandler, flags = flags)
    ts.httpServer = server
    server.start()
    ts.port = server.localAddress().port.int
    ts

  proc stop(ts: TestWsServer) {.async: (raises: []).} =
    try:
      ts.httpServer.stop()
      await ts.httpServer.closeWait()
    except CancelledError:
      discard
    except CatchableError:
      discard

  proc wsUrl(port: int): string = "ws://127.0.0.1:" & $port & "/"

  suite "websock firewall (G1-only)":
    setup:
      while currentVerifier() != nil:
        discard popVerifier()

    # ------------------------------------------------------------------
    # 1. G1 raises on unmocked websock connect inside sandbox
    # ------------------------------------------------------------------
    test "connect: unmocked call inside sandbox raises UnmockedInteractionDefect":
      ## The TRM body fires before any network connect can begin. The
      ## URL points to a never-bound address; if the firewall fails open
      ## the test would hang on connect-timeout, not on a network round
      ## trip — the never-bound URL is defense in depth.
      expect UnmockedInteractionDefect:
        sandbox:
          let parsed = parseUri(NeverBoundUrl)
          # connect() is the TRM-intercepted entry point — this raises
          # before websock opens a socket.
          discard waitFor nfwebsockConnect(parsed)

    # ------------------------------------------------------------------
    # 2. allow(plugin, M(host="127.0.0.1")) — real round-trip via TRM
    #    passthrough to the localhost listener
    # ------------------------------------------------------------------
    test "allow(M(host=127.0.0.1)) authorizes loopback round-trip":
      let ts = startTestWsServer()
      defer:
        waitFor ts.stop()
      sandbox:
        allow(websockPluginInstance, M(host = "127.0.0.1"))
        let parsed = parseUri(wsUrl(ts.port))
        let session = waitFor nfwebsockConnect(parsed)
        check session != nil
        check session.readyState == ReadyState.Open
        let bytes = waitFor session.recvMsg()
        var s = newString(bytes.len)
        for i in 0 ..< bytes.len:
          s[i] = char(bytes[i])
        check s == "hello-from-tripwire-test"
        waitFor session.close()
        # Firewall passthrough recorded the interaction; auto-drain
        # (e13fd15) makes G2 ignore ikFirewallPassthrough on sandbox
        # exit. No markAsserted loop required.

    # ------------------------------------------------------------------
    # 3. allow(plugin) blanket — round-trip works regardless of host
    # ------------------------------------------------------------------
    test "allow(plugin) blanket authorizes any websock connect":
      let ts = startTestWsServer()
      defer:
        waitFor ts.stop()
      sandbox:
        allow(websockPluginInstance)
        let parsed = parseUri(wsUrl(ts.port))
        let session = waitFor nfwebsockConnect(parsed)
        check session != nil
        waitFor session.close()

    # ------------------------------------------------------------------
    # 4. restrict ceiling — broad allow narrowed to loopback only;
    #    non-loopback URL falls outside the ceiling and raises.
    # ------------------------------------------------------------------
    test "restrict(M(host=127.0.0.1)) narrows blanket allow":
      expect UnmockedInteractionDefect:
        sandbox:
          allow(websockPluginInstance)                            # broad
          restrict(websockPluginInstance,
                   M(host = "127.0.0.1"))                          # ceiling
          # Non-loopback host — falls outside the ceiling, must raise
          # even though `allow` is blanket.
          let parsed = parseUri(NeverBoundUrl)
          discard waitFor nfwebsockConnect(parsed)

    test "restrict(M(host=127.0.0.1)) admits loopback round-trip":
      let ts = startTestWsServer()
      defer:
        waitFor ts.stop()
      sandbox:
        allow(websockPluginInstance)
        restrict(websockPluginInstance, M(host = "127.0.0.1"))
        let parsed = parseUri(wsUrl(ts.port))
        let session = waitFor nfwebsockConnect(parsed)
        check session != nil
        waitFor session.close()

    # ------------------------------------------------------------------
    # 5. fmWarn mode — unmocked call emits stderr warning, falls through
    #    to the real websock proc. The websock call subsequently fails
    #    against the never-bound URL (network error). The test asserts
    #    the FIREWALL did NOT raise UnmockedInteractionDefect; whether
    #    websock itself succeeds is orthogonal.
    # ------------------------------------------------------------------
    test "fmWarn: unmocked call falls through (firewall does not raise)":
      sandbox:
        let v = currentVerifier()
        guard(v, fmWarn)
        let parsed = parseUri(NeverBoundUrl)
        # Bound the connect attempt so a misbehaving firewall (or a
        # network stack that holds the SYN open) doesn't hang the test.
        # In fmWarn the firewall MUST NOT raise UnmockedInteractionDefect;
        # the websock call itself is allowed to fail however it likes.
        var firewallRaised = false
        var websockFailed = false
        try:
          discard waitFor chronos.wait(
            nfwebsockConnect(parsed), 2.seconds)
        except UnmockedInteractionDefect:
          firewallRaised = true
        except CatchableError:
          websockFailed = true
        # The firewall MUST NOT have raised the tripwire defect; websock
        # itself MAY have raised a network error or timed out.
        check (not firewallRaised)
        # We expect websock to fail (never-bound URL) — but accept any
        # outcome here, since the OS routing matters. The load-bearing
        # invariant is that the firewall let it through.
        discard websockFailed
        discard v
else:
  discard
