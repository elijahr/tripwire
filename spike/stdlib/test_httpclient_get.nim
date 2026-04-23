## Target 1: std/httpclient HttpClient.get(url: string): Response
##
## Dotted call shape, method-style on a ref object. Sync proc (multisync
## expanded): `proc get(client: HttpClient, url: string): Response`.
##
## We never make the real request; the TRM should intercept and return
## a nil Response sentinel.
import std/httpclient

var rewriteCount {.global.} = 0

template rewriteGet{get(client, url)}(client: HttpClient, url: string): Response =
  inc(rewriteCount)
  Response(nil)

let c = newHttpClient()
let r = c.get("http://example.invalid/")
echo "got nil? ", r.isNil, " rewriteCount=", rewriteCount
