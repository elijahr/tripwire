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
import std/[httpclient, streams, asyncdispatch, uri, tables, options, macros]
import ../[types, registry, timeline, sandbox, verify, intercept, futures]
import ../macros as nfmacros
import ./plugin_intercept

export plugin_intercept.nimfootPluginIntercept
export nfmacros.respond, nfmacros.responded, nfmacros.request

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

method realize*(r: HttpMockResponse): Response {.base.} =
  ## Build a Response that mirrors what the real httpclient would produce.
  ## `body` is read lazily from `bodyStream` via the `httpclient.body()`
  ## getter, so we set only `bodyStream` (the `body` field is not
  ## exported from std/httpclient).
  result = Response(
    version: "1.1",
    status: $r.status,
    headers: (if r.headers.isNil: newHttpHeaders() else: r.headers),
    bodyStream: newStringStream(r.body))

method realize*(r: HttpAsyncMockResponse): Future[AsyncResponse] {.base.} =
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

# ---- Async request TRM ---------------------------------------------------
template requestAsyncTRM*{request(c, url, httpMethod, body, headers, multipart)}(
    c: AsyncHttpClient, url: string, httpMethod: HttpMethod = HttpGet,
    body: string = "", headers: HttpHeaders = nil,
    multipart: MultipartData = nil): Future[AsyncResponse] =
  nimfootPluginIntercept(
    httpclientPluginInstance,
    "request",
    fingerprintHttpRequest(url, httpMethod, body, headers, multipart),
    HttpAsyncMockResponse):
    {.noRewrite.}:
      request(c, url, httpMethod, body, headers, multipart)

# ---- Uri-overload TRMs (fingerprint the Uri as its $uri form) -----------
template requestSyncUriTRM*{request(c, url, httpMethod, body, headers, multipart)}(
    c: HttpClient, url: Uri, httpMethod: HttpMethod = HttpGet,
    body: string = "", headers: HttpHeaders = nil,
    multipart: MultipartData = nil): Response =
  nimfootPluginIntercept(
    httpclientPluginInstance,
    "request",
    fingerprintHttpRequest($url, httpMethod, body, headers, multipart),
    HttpMockResponse):
    {.noRewrite.}:
      request(c, url, httpMethod, body, headers, multipart)

template requestAsyncUriTRM*{request(c, url, httpMethod, body, headers, multipart)}(
    c: AsyncHttpClient, url: Uri, httpMethod: HttpMethod = HttpGet,
    body: string = "", headers: HttpHeaders = nil,
    multipart: MultipartData = nil): Future[AsyncResponse] =
  nimfootPluginIntercept(
    httpclientPluginInstance,
    "request",
    fingerprintHttpRequest($url, httpMethod, body, headers, multipart),
    HttpAsyncMockResponse):
    {.noRewrite.}:
      request(c, url, httpMethod, body, headers, multipart)

# ---- F6: Wrapper canonicalization ---------------------------------------
# Map each httpclient wrapper verb to the canonical HttpMethod the TRM
# sees after stdlib's internal call-through. Values match HttpMethod
# enum names so parseEnum[HttpMethod] round-trips.
const WrapperMethodMap = {
  "get": "HttpGet", "post": "HttpPost", "put": "HttpPut",
  "delete": "HttpDelete", "patch": "HttpPatch", "head": "HttpHead",
  "getContent": "HttpGet", "postContent": "HttpPost",
  "deleteContent": "HttpDelete", "putContent": "HttpPut",
  "patchContent": "HttpPatch"
}.toTable

proc extractRespondFields(body: NimNode,
    verbNames: openArray[string]): Table[string, NimNode] =
  ## Parse `respond:` / `responded:` block in expectHttp / assertHttp body.
  ## Accepts either of:
  ##   respond:
  ##     status: 200
  ##     body: "ok"
  ##   respond status: 200, body: "ok"   (single-line command form)
  ## Returns a map of fieldName -> valueExpr for fields mentioned.
  result = initTable[string, NimNode]()
  for stmt in body:
    if stmt.kind notin {nnkCommand, nnkCall}: continue
    if stmt.len < 1 or stmt[0].kind != nnkIdent: continue
    var matched = false
    for v in verbNames:
      if stmt[0].strVal == v: matched = true; break
    if not matched: continue
    # Block form: Command(verb, StmtList(ExprColonExpr(field, val), ...))
    # OR Command(verb, ExprColonExpr(field, val), ...) single line.
    for i in 1 ..< stmt.len:
      let sub = stmt[i]
      case sub.kind
      of nnkStmtList:
        for colon in sub:
          if colon.kind == nnkCall and colon.len == 2 and
             colon[0].kind == nnkIdent and colon[1].kind == nnkStmtList and
             colon[1].len == 1:
            # Parsed as Call(Ident "status", StmtList(200))
            result[colon[0].strVal] = colon[1][0]
          elif colon.kind == nnkExprColonExpr and colon[0].kind == nnkIdent:
            result[colon[0].strVal] = colon[1]
      of nnkExprColonExpr:
        if sub[0].kind == nnkIdent:
          result[sub[0].strVal] = sub[1]
      of nnkIdent:
        # Pair pattern: Ident followed by StmtList
        if i + 1 < stmt.len and stmt[i + 1].kind == nnkStmtList:
          let rhs = stmt[i + 1]
          if rhs.len == 1:
            result[sub.strVal] = rhs[0]
      else:
        discard

macro expectHttp*(call: untyped, body: untyped): untyped =
  ## `expectHttp get(c, url): respond: status: S, body: B`
  ##
  ## Canonicalizes the wrapper call to a `request` Mock registration so
  ## the sync/async TRM for `request` consumes it. Supports get, post,
  ## put, delete, patch, head, and the *Content variants.
  ##
  ## `call` is `untyped` (not `typed`) because the proc signatures of
  ## httpclient's `get`/`post`/... include default `headers` etc. that
  ## would complicate typed resolution; we only need the verb name and
  ## positional args at macro-expansion time.
  expectKind(call, nnkCall)
  let fnName = $call[0]
  if fnName notin WrapperMethodMap:
    error("expectHttp only supports get/post/put/delete/patch/head and" &
          " their *Content variants; got: " & fnName, call)
  let httpMethodIdent = newIdentNode(WrapperMethodMap[fnName])
  if call.len < 3:
    error("expectHttp " & fnName & "(c, url, ...): missing client or URL",
          call)
  let client = call[1]
  let url = call[2]
  let reqBody = if call.len > 3: call[3] else: newLit("")

  let fields = extractRespondFields(body, ["respond"])
  let status = if "status" in fields: fields["status"] else: newLit(200)
  let respBody = if "body" in fields: fields["body"] else: newLit("")
  discard client  # client is used via the TRM; not needed at registration time.

  result = quote do:
    registerMock(currentVerifier(), "httpclient",
      newMock("request",
        fingerprintHttpRequest(`url`, `httpMethodIdent`,
          `reqBody`, nil, nil),
        HttpMockResponse(status: `status`, body: `respBody`,
                         headers: newHttpHeaders()),
        instantiationInfo()))

macro assertHttp*(call: untyped, body: untyped): untyped =
  ## `assertHttp get(c, url): responded: status: 200`
  ##
  ## Finds the next unasserted `request` Interaction in the verifier's
  ## timeline with a matching fingerprint (url + method + body + nil
  ## headers/multipart), checks the response's status field, and marks
  ## it asserted.
  expectKind(call, nnkCall)
  let fnName = $call[0]
  if fnName notin WrapperMethodMap:
    error("assertHttp only supports canonical wrappers; got: " & fnName, call)
  let httpMethodIdent = newIdentNode(WrapperMethodMap[fnName])
  let url = call[2]
  let reqBody = if call.len > 3: call[3] else: newLit("")

  let fields = extractRespondFields(body, ["responded"])
  let expectedStatus = if "status" in fields: fields["status"] else: newLit(200)

  result = quote do:
    block:
      let nfHV = currentVerifier()
      doAssert nfHV != nil, "assertHttp outside sandbox"
      let nfHFp = fingerprintHttpRequest(`url`, `httpMethodIdent`,
        `reqBody`, nil, nil)
      var nfHFound: Interaction = nil
      for e in nfHV.timeline.entries:
        if not e.asserted and e.procName == "request" and
           ".fp" in e.args and e.args[".fp"] == nfHFp:
          nfHFound = e
          break
      doAssert nfHFound != nil,
        "assertHttp: no unasserted request interaction for " & nfHFp
      let nfHResp = HttpMockResponse(nfHFound.response)
      doAssert nfHResp.status == `expectedStatus`,
        "assertHttp: status mismatch for " & nfHFp
      nfHV.timeline.markAsserted(nfHFound)
