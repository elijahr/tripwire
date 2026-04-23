## tests/test_httpclient_plugin.nim — F4: httpclient plugin base + sync request TRM.
import std/[unittest, httpclient, options, strutils]
import nimfoot/[types, errors, timeline, sandbox, verify, intercept,
                macros as nfmacros]
import nimfoot/plugins/httpclient as nfhttp

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
