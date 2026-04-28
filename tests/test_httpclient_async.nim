## tests/test_httpclient_async.nim — F5: async TRM + Uri overload.
import std/[unittest, httpclient, uri, asyncdispatch]
import tripwire/auto
# `newMock`, `registerMock`, `markAsserted`, `fingerprintHttpRequest`,
# `HttpAsyncMockResponse`, and `HttpMockResponse` are all
# plugin-author-facing helpers. They're intentionally not exported
# through `tripwire/auto`, so this test still imports them directly.
import tripwire/[types, verify, timeline]
import tripwire/plugins/httpclient as nfhttp

proc doAsyncRequest(c: AsyncHttpClient, url: string): Future[AsyncResponse] =
  c.request(url)

proc doSyncUriRequest(c: HttpClient, url: Uri): Response =
  c.request(url)

suite "httpclient async":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "async request returns Future[AsyncResponse]":
    sandbox:
      let v = currentVerifier()
      let m = newMock("request",
        fingerprintHttpRequest("http://async.example", HttpGet, "", nil, nil),
        HttpAsyncMockResponse(status: 200, body: "async-ok",
                              headers: newHttpHeaders()),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(v, "httpclient", m)
      let c = newAsyncHttpClient()
      let r = waitFor doAsyncRequest(c, "http://async.example")
      check r.status == "200"
      v.timeline.markAsserted(v.timeline.entries[0])

  test "sync Uri overload fires":
    sandbox:
      let v = currentVerifier()
      let m = newMock("request",
        fingerprintHttpRequest("http://uri.example", HttpGet, "", nil, nil),
        HttpMockResponse(status: 200, body: "u", headers: newHttpHeaders()),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(v, "httpclient", m)
      let c = newHttpClient()
      let r = doSyncUriRequest(c, parseUri("http://uri.example"))
      check r.status == "200"
      v.timeline.markAsserted(v.timeline.entries[0])
