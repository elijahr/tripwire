## Q2 (variant A): Does a TRM fire on multisync-generated AsyncHttpClient.get?
##
## Strategy: instead of trying to construct a fake AsyncResponse (whose fields
## may be private), the TRM body raises a distinctive exception. If the
## rewrite fires, `waitFor` will surface that exception and we can catch it.
## If the rewrite does NOT fire, the real call will attempt a network fetch
## to an invalid host — we give it a short runway and expect the TRM-fired
## exception to appear first.
import std/[asyncdispatch, httpclient]

type MarkerError = object of CatchableError

var asyncRewrites* = 0

template rewriteAsyncGet*{get(c, url)}(c: AsyncHttpClient, url: string): Future[AsyncResponse] =
  inc(asyncRewrites)
  let f = newFuture[AsyncResponse]("fakeAsyncGet")
  f.fail(newException(MarkerError, "TRM fired on AsyncHttpClient.get"))
  f

let c = newAsyncHttpClient()
var sawMarker = false
var otherError = ""
try:
  discard waitFor c.get("http://example.invalid/")
except MarkerError as e:
  sawMarker = true
  echo "caught MarkerError: ", e.msg
except CatchableError as e:
  otherError = $e.name & ": " & e.msg
  echo "caught OTHER error: ", otherError

echo "asyncRewrites=", asyncRewrites
echo "sawMarker=", sawMarker
