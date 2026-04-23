## nimfoot/plugins/httpclient.nim — std/httpclient interception.
##
## Design §12.2: intercept at the `request` level, not per-wrapper.
## TRM signature defaults MUST match std/httpclient 2.2.6 exactly:
##   headers: HttpHeaders = nil   (NOT newHttpHeaders())
## Otherwise stdlib default elaboration (`c.request(url)` elaborates to
## `request(c, url, HttpGet, "", nil, nil)` pre-TRM) won't match our
## 6-arg pattern. Validated by the F4 smoke probe at design/impl time.
##
## Notes on `Response`:
##
## * `Response.body` is NOT exported by `std/httpclient` — the `body()`
##   getter lazily reads from `bodyStream`. Constructing a Response
##   here sets `bodyStream` to a `StringStream` carrying the mocked
##   body; the caller's `r.body` then reads it correctly.
## * Using `nimfootPluginIntercept` (from ./plugin_intercept) rather than
##   `nimfootInterceptBody` (from ../intercept): the latter declares
##   `respType: typedesc`, which silently breaks TRM pattern matching
##   in Nim 2.2.6. See plugin_intercept.nim for the analysis.
import std/[httpclient, streams, asyncdispatch, tables, options]
import ../[types, registry, timeline, sandbox, verify, intercept, futures]
import ./plugin_intercept

export plugin_intercept.nimfootPluginIntercept

type
  HttpclientPlugin* = ref object of Plugin
  HttpMockResponse* = ref object of MockResponse
    status*: int
    headers*: HttpHeaders
    body*: string
  HttpAsyncMockResponse* = ref object of MockResponse
    status*: int
    headers*: HttpHeaders
    body*: string

proc fingerprintHttpRequest*(url: string, httpMethod: HttpMethod,
                             body: string, headers: HttpHeaders,
                             multipart: MultipartData): string =
  ## Canonicalize a request's identifying fields into a stable string.
  ## `headers` and `multipart` may be nil — $nil prints as "nil".
  $httpMethod & " " & url & " body=" & body &
  " hdr=" & (if headers.isNil: "nil" else: $headers) &
  " mp=" & (if multipart.isNil: "nil" else: "multipart")

method realize*(r: HttpMockResponse): Response =
  ## Build a Response that mirrors what the real httpclient would produce.
  ## `body` is read lazily from `bodyStream` via the `httpclient.body()`
  ## getter, so we set only `bodyStream` (the `body` field is not
  ## exported from std/httpclient).
  result = Response(
    version: "1.1",
    status: $r.status,
    headers: (if r.headers.isNil: newHttpHeaders() else: r.headers),
    bodyStream: newStringStream(r.body))

method realize*(r: HttpAsyncMockResponse): Future[AsyncResponse] =
  ## Async counterpart. `AsyncResponse.body` is also unexported; we set
  ## only the fields we can construct and let the stdlib's `body()`
  ## future lazily materialize the body string.
  let ar = AsyncResponse(version: "1.1", status: $r.status,
    headers: (if r.headers.isNil: newHttpHeaders() else: r.headers))
  makeCompletedFuture(ar, "httpclient.request")

let httpclientPluginInstance* = HttpclientPlugin(name: "httpclient",
                                                  enabled: true)
registerPlugin(httpclientPluginInstance)

# ---- Sync request TRM ----------------------------------------------------
# Six-arg pattern binds a one-arg call because stdlib defaults elaborate
# pre-TRM (per F4 smoke probe). Defaults MUST match std/httpclient 2.2.6.
template requestSyncTRM*{request(c, url, httpMethod, body, headers, multipart)}(
    c: HttpClient, url: string, httpMethod: HttpMethod = HttpGet,
    body: string = "", headers: HttpHeaders = nil,
    multipart: MultipartData = nil): Response =
  nimfootPluginIntercept(
    httpclientPluginInstance,
    "request",
    fingerprintHttpRequest(url, httpMethod, body, headers, multipart),
    HttpMockResponse):
    {.noRewrite.}:
      request(c, url, httpMethod, body, headers, multipart)
