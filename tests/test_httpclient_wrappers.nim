## tests/test_httpclient_wrappers.nim — F6: wrapper canonicalization DSL.
import std/[unittest, httpclient, options, tables]
import nimfoot/[types, errors, timeline, sandbox, verify, intercept,
                macros as nfmacros]
import nimfoot/plugins/httpclient as nfhttp

# Wrapper procs — see test_mock_expect.nim gotcha.
proc doGet(c: HttpClient, url: string): Response = c.get(url)
proc doPost(c: HttpClient, url, body: string): Response = c.post(url, body = body)

suite "httpclient wrapper canonicalization":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "expect get / c.get / assert responded":
    sandbox:
      let c = newHttpClient()
      nfhttp.expectHttp get(c, "http://ex.com"):
        respond:
          status: 200
          body: "ok"
      let r = doGet(c, "http://ex.com")
      check r.status == "200"
      check r.body == "ok"
      nfhttp.assertHttp get(c, "http://ex.com"):
        responded:
          status: 200

  test "expect post with body":
    sandbox:
      let c = newHttpClient()
      nfhttp.expectHttp post(c, "http://ex.com", "payload"):
        respond:
          status: 201
          body: "created"
      let r = doPost(c, "http://ex.com", "payload")
      check r.status == "201"
      nfhttp.assertHttp post(c, "http://ex.com", "payload"):
        responded:
          status: 201
