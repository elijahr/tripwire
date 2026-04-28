## tests/test_chronos_httpclient_firewall.nim — chronos httpclient
## firewall-only plugin behavioral tests (G1 enforcement, allow/restrict
## interaction, fmWarn lane).
##
## Gated at module scope by `when defined(chronos)` so the file is a
## no-op when compiled without `-d:chronos`. The standalone chronos cell
## (`TRIPWIRE_TEST_CHRONOS=1` → cell #6 in tripwire.nimble) exercises
## it; default cells skip silently.
##
## ## Why this file is its own standalone cell
##
## The chronos firewall plugin emits three TRMs (`send`, `fetch(uri)`,
## `fetch(req)`) that each count toward Defense 3's
## 15-rewrites-per-compilation-unit cap (`cap_counter.nim`). Combined
## with the existing chronos cell's TRM rewrites
## (`test_async_chronos.nim`, the umbrella plugin set), the aggregate
## is at risk of going over. Following the precedent set by
## `test_osproc_arrays.nim` and `test_firewall.nim`, this file lives in
## its own cell so its TRM expansions never compete with the aggregate's.
when defined(chronos):
  import std/[unittest, strutils, os]
  import chronos
  import chronos/apps/http/[httpclient, httpcommon, httpserver, httptable]
  import tripwire/[types, errors, sandbox, verify, timeline]
  import tripwire/plugins/chronos_httpclient as nfchronos

  # ------------------------------------------------------------------
  # Test fixtures
  # ------------------------------------------------------------------

  # A never-bound IP+port so a firewall miss raises before any real
  # network round-trip can hang the test. RFC 5737 documentation prefix
  # 192.0.2.0/24 routes nowhere; a connection attempt fails immediately
  # on most stacks. We use port 1 (privileged, never listening) for an
  # extra signal in case the test harness disagrees with us about
  # routability.
  const NeverBoundUrl = "http://192.0.2.1:1/never"

  proc helloHandler(r: RequestFence): Future[HttpResponseRef] {.
      async: (raises: [CancelledError]).} =
    ## Minimal HTTP handler for the localhost listener tests. Always
    ## returns 200 with a sentinel body. RequestFence carries either an
    ## HttpRequestRef or an error; on error we raise so chronos closes
    ## the connection cleanly.
    if r.isErr:
      raise (ref CancelledError)(msg: "request fence: " & $r.error.kind)
    let req = r.get()
    try:
      return await req.respond(Http200, "hello-from-localhost")
    except HttpWriteError as exc:
      raise (ref CancelledError)(msg: "respond write: " & exc.msg)
    except CancelledError as exc:
      raise exc

  proc startLocalhostServer(): tuple[server: HttpServerRef, port: int] =
    ## Spawn an HttpServer on a random localhost port. Returns the live
    ## server (caller must `closeWait`) and the bound port.
    let addr0 = initTAddress("127.0.0.1:0")
    let res = HttpServerRef.new(addr0, helloHandler)
    doAssert res.isOk, "http server bind failed: " & res.error
    let server = res.get()
    server.start()
    (server: server, port: int(server.address.port))

  # Wrap chronos's session creation in a thin helper so each test owns a
  # fresh session (avoids cross-test connection-pool contamination on
  # TIME_WAIT cleanup).
  proc newSession(): HttpSessionRef =
    HttpSessionRef.new(flags = {HttpClientFlag.Http11Pipeline})

  suite "chronos httpclient firewall (G1-only)":
    setup:
      while currentVerifier() != nil:
        discard popVerifier()

    # ------------------------------------------------------------------
    # 1. G1 raises on unmocked chronos call inside sandbox
    # ------------------------------------------------------------------
    test "send: unmocked call inside sandbox raises UnmockedInteractionDefect":
      ## The TRM body fires before any network connect can begin. The
      ## URL points to a never-bound address; if the firewall fails open
      ## the test would hang on connect-timeout, not on a network round
      ## trip — the never-bound URL is defense in depth.
      expect UnmockedInteractionDefect:
        sandbox:
          let session = newSession()
          let reqRes = HttpClientRequestRef.post(
            session, NeverBoundUrl, body = "")
          doAssert reqRes.isOk, "request build failed: " & reqRes.error
          let req = reqRes.get()
          # send() is the TRM-intercepted entry point — this raises
          # before chronos opens a socket.
          discard waitFor req.send()
          # Unreachable; the firewall already raised. Belt-and-braces
          # cleanup uses waitFor (test bodies aren't async procs).
          waitFor req.closeWait()
          waitFor session.closeWait()

    test "fetch(session, url): unmocked call raises UnmockedInteractionDefect":
      expect UnmockedInteractionDefect:
        sandbox:
          let session = newSession()
          discard waitFor session.fetch(parseUri(NeverBoundUrl))
          waitFor session.closeWait()

    test "fetch(req): unmocked call inside sandbox raises UnmockedInteractionDefect":
      ## Regression guard for the silent firewall bypass on the
      ## request-form `fetch`. Prior to chronosFetchReqTRM, the
      ## existing `send` TRM did NOT transitively cover this code
      ## path: chronos's `fetch(req)` body compiles outside the
      ## tripwire-active compilation unit, so the inner `request.send()`
      ## call inside chronos is not subject to TRM rewriting.
      ## Without the new TRM this test reaches the network and either
      ## hangs or surfaces a network error — NOT
      ## UnmockedInteractionDefect.
      expect UnmockedInteractionDefect:
        sandbox:
          let session = newSession()
          let reqRes = HttpClientRequestRef.post(
            session, NeverBoundUrl, body = "")
          doAssert reqRes.isOk, "request build failed: " & reqRes.error
          let req = reqRes.get()
          discard waitFor req.fetch()
          # Unreachable; the firewall already raised. Belt-and-braces
          # cleanup uses waitFor (test bodies aren't async procs).
          waitFor req.closeWait()
          waitFor session.closeWait()

    # ------------------------------------------------------------------
    # 2. allow(plugin, M(host="127.0.0.1")) — real round-trip via TRM
    #    passthrough to the localhost listener
    # ------------------------------------------------------------------
    test "allow(M(host=127.0.0.1)) authorizes loopback round-trip":
      let (server, port) = startLocalhostServer()
      defer:
        waitFor server.closeWait()
      sandbox:
        let v = currentVerifier()
        allow(chronosHttpPluginInstance, M(host = "127.0.0.1"))
        let session = newSession()
        let url = "http://127.0.0.1:" & $port & "/hello"
        let reqRes = HttpClientRequestRef.post(
          session, url, body = "ping")
        doAssert reqRes.isOk, "request build failed: " & reqRes.error
        let req = reqRes.get()
        let resp = waitFor req.send()
        check resp.status == 200
        let bodyBytes = waitFor resp.getBodyBytes()
        var body = newString(bodyBytes.len)
        for i in 0 ..< bodyBytes.len:
          body[i] = char(bodyBytes[i])
        check body == "hello-from-localhost"
        waitFor resp.closeWait()
        waitFor req.closeWait()
        waitFor session.closeWait()
        # The firewall passthrough recorded the interaction; mark it
        # asserted so verifyAll doesn't fire UnassertedInteractionsDefect
        # on sandbox exit (G2 is not the firewall's job, but the
        # combinator still records — same rule the existing httpclient
        # tests follow).
        check v.timeline.entries.len >= 1
        for entry in v.timeline.entries:
          v.timeline.markAsserted(entry)

    test "fetch(req): allow(M(host=127.0.0.1)) authorizes loopback round-trip":
      ## Mirrors the `send` passthrough test for the request-form
      ## `fetch`. With chronosFetchReqTRM in place, the firewall
      ## consults the matcher BEFORE chronos's body executes; on
      ## allow, the trampoline calls real chronos which does its own
      ## `request.send()` to the localhost listener and returns the
      ## (status, body) tuple.
      let (server, port) = startLocalhostServer()
      defer:
        waitFor server.closeWait()
      sandbox:
        let v = currentVerifier()
        allow(chronosHttpPluginInstance, M(host = "127.0.0.1"))
        let session = newSession()
        let url = "http://127.0.0.1:" & $port & "/fetch-req"
        let reqRes = HttpClientRequestRef.post(
          session, url, body = "ping")
        doAssert reqRes.isOk, "request build failed: " & reqRes.error
        let req = reqRes.get()
        let (status, bodyBytes) = waitFor req.fetch()
        check status == 200
        var body = newString(bodyBytes.len)
        for i in 0 ..< bodyBytes.len:
          body[i] = char(bodyBytes[i])
        check body == "hello-from-localhost"
        waitFor req.closeWait()
        waitFor session.closeWait()
        check v.timeline.entries.len >= 1
        for entry in v.timeline.entries:
          v.timeline.markAsserted(entry)

    # ------------------------------------------------------------------
    # 3. allow(plugin) blanket — round-trip works regardless of host
    # ------------------------------------------------------------------
    test "allow(plugin) blanket authorizes any chronos http call":
      let (server, port) = startLocalhostServer()
      defer:
        waitFor server.closeWait()
      sandbox:
        let v = currentVerifier()
        allow(chronosHttpPluginInstance)
        let session = newSession()
        let url = "http://127.0.0.1:" & $port & "/blanket"
        let reqRes = HttpClientRequestRef.post(
          session, url, body = "")
        doAssert reqRes.isOk
        let req = reqRes.get()
        let resp = waitFor req.send()
        check resp.status == 200
        waitFor resp.closeWait()
        waitFor req.closeWait()
        waitFor session.closeWait()
        for entry in v.timeline.entries:
          v.timeline.markAsserted(entry)

    # ------------------------------------------------------------------
    # 4. restrict ceiling — broad allow narrowed to loopback only;
    #    non-loopback URL falls outside the ceiling and raises.
    # ------------------------------------------------------------------
    test "restrict(M(host=127.0.0.1)) narrows blanket allow":
      expect UnmockedInteractionDefect:
        sandbox:
          allow(chronosHttpPluginInstance)                     # broad
          restrict(chronosHttpPluginInstance,
                   M(host = "127.0.0.1"))                       # ceiling
          let session = newSession()
          # Non-loopback host — falls outside the ceiling, must raise
          # even though `allow` is blanket.
          let reqRes = HttpClientRequestRef.post(
            session, NeverBoundUrl, body = "")
          doAssert reqRes.isOk
          let req = reqRes.get()
          discard waitFor req.send()

    test "restrict(M(host=127.0.0.1)) admits loopback round-trip":
      let (server, port) = startLocalhostServer()
      defer:
        waitFor server.closeWait()
      sandbox:
        let v = currentVerifier()
        allow(chronosHttpPluginInstance)
        restrict(chronosHttpPluginInstance, M(host = "127.0.0.1"))
        let session = newSession()
        let url = "http://127.0.0.1:" & $port & "/inside-ceiling"
        let reqRes = HttpClientRequestRef.post(
          session, url, body = "")
        doAssert reqRes.isOk
        let req = reqRes.get()
        let resp = waitFor req.send()
        check resp.status == 200
        waitFor resp.closeWait()
        waitFor req.closeWait()
        waitFor session.closeWait()
        for entry in v.timeline.entries:
          v.timeline.markAsserted(entry)

    # ------------------------------------------------------------------
    # 5. fmWarn mode — unmocked call emits stderr warning, falls through
    #    to the real chronos proc. The chronos call subsequently fails
    #    against the never-bound URL (network error). The test asserts
    #    the FIREWALL did NOT raise UnmockedInteractionDefect; whether
    #    chronos itself succeeds is orthogonal.
    # ------------------------------------------------------------------
    test "fmWarn: unmocked call falls through (firewall does not raise)":
      sandbox:
        let v = currentVerifier()
        guard(v, fmWarn)
        let session = newSession()
        let reqRes = HttpClientRequestRef.post(
          session, NeverBoundUrl, body = "")
        doAssert reqRes.isOk
        let req = reqRes.get()
        # Bound the connect attempt so a misbehaving firewall (or a
        # network stack that holds the SYN open) doesn't hang the test.
        # In fmWarn the firewall MUST NOT raise UnmockedInteractionDefect;
        # the chronos call itself is allowed to fail however it likes.
        var firewallRaised = false
        var chronosFailed = false
        try:
          discard waitFor chronos.wait(req.send(), 2.seconds)
        except UnmockedInteractionDefect:
          firewallRaised = true
        except CatchableError:
          chronosFailed = true
        # The firewall MUST NOT have raised the tripwire defect; chronos
        # itself MAY have raised a network error or timed out.
        check (not firewallRaised)
        # We expect chronos to fail (never-bound URL) — but accept any
        # outcome here, since the OS routing matters. The load-bearing
        # invariant is that the firewall let it through.
        discard chronosFailed
        waitFor req.closeWait()
        waitFor session.closeWait()
        for entry in v.timeline.entries:
          v.timeline.markAsserted(entry)
else:
  discard
