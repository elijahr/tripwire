## Target 2: std/httpclient HttpClient.request
## Sync signature: proc request(client: HttpClient, url: string,
##   httpMethod: HttpMethod, body: string, headers: HttpHeaders,
##   multipart: MultipartData): Response
##
## The sync form has 6 params (the sixth `multipart` defaults to nil).
## The TRM declares all six explicitly.
import std/httpclient

var rewriteCount {.global.} = 0

template rewriteRequest{request(client, url, httpMethod, body, headers, multipart)}(
    client: HttpClient, url: string, httpMethod: HttpMethod, body: string,
    headers: HttpHeaders, multipart: MultipartData): Response =
  inc(rewriteCount)
  Response(nil)

let c = newHttpClient()
let r = c.request("http://example.invalid/", HttpPost, "body=1",
                  newHttpHeaders(), nil)
echo "got nil? ", r.isNil, " rewriteCount=", rewriteCount
