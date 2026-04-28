## tests/test_httpclient_plugin.nim — F4: httpclient plugin base + sync request TRM.
import std/[unittest, httpclient, options, strutils]
import tripwire/[types, errors, timeline, sandbox, verify, intercept,
                macros as nfmacros]
import tripwire/plugins/httpclient as nfhttp

# Wrapper proc — TRM-on-direct-call-in-test gotcha (see test_mock_expect.nim).
proc doRequest(c: HttpClient, url: string): Response =
  c.request(url)

suite "httpclient plugin":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "plugin registered":
    check httpclientPluginInstance != nil
    check httpclientPluginInstance.name == "httpclient"

  test "fingerprintHttpRequest deterministic":
    let fp1 = fingerprintHttpRequest("http://x", HttpGet, "", nil, nil)
    let fp2 = fingerprintHttpRequest("http://x", HttpGet, "", nil, nil)
    check fp1 == fp2
    check fp1 != fingerprintHttpRequest("http://y", HttpGet, "", nil, nil)

  test "fingerprintHttpRequest distinguishes query strings":
    # Two URLs identical except for query parameters MUST yield distinct
    # fingerprints, otherwise mocking `/api?id=1` would also match
    # `/api?id=2` (a Guarantee 1 / Guarantee 2 interaction-uniqueness
    # violation). Mirrors the chronos_httpclient/websock plugin behavior.
    let fp1 = fingerprintHttpRequest("http://example.com/api?id=1",
                                     HttpGet, "", nil, nil)
    let fp2 = fingerprintHttpRequest("http://example.com/api?id=2",
                                     HttpGet, "", nil, nil)
    check fp1 != fp2
    check "query=id=1" in fp1
    check "query=id=2" in fp2

  test "fingerprintHttpRequest fills default port from scheme":
    # `M(port=80)` should match URLs that omit the port for http (and
    # similarly 443 for https). The chronos_httpclient/websock plugins
    # already normalize default ports; this test pins the parity for
    # std/httpclient.
    let httpFp  = fingerprintHttpRequest("http://example.com/",
                                         HttpGet, "", nil, nil)
    let httpsFp = fingerprintHttpRequest("https://example.com/",
                                         HttpGet, "", nil, nil)
    check "port=80" in httpFp
    check "port=443" in httpsFp

  test "sync request TRM binds and returns mocked response":
    ## CRITICAL EARLY INTEGRATION: verifies TRM default (headers = nil)
    ## matches stdlib 2.2.6. If this fails, the plugin is broken at
    ## the most fundamental level.
    sandbox:
      let v = currentVerifier()
      let m = newMock("request",
        fingerprintHttpRequest("http://example.com", HttpGet, "", nil, nil),
        HttpMockResponse(status: 200, body: "ok",
                         headers: newHttpHeaders()),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(v, "httpclient", m)
      let c = newHttpClient()
      let r = doRequest(c, "http://example.com")
      check r.status == "200"
      check r.body == "ok"
      v.timeline.markAsserted(v.timeline.entries[0])
