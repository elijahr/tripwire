## Target 7 (substitute for db_sqlite, which is no longer bundled with Nim 2.2):
## Test varargs[string] matching against std/cgi.setTestData.
##
## Two variants: (a) TRM declares varargs[string] literally, (b) TRM declares
## openArray[string] (common metatype workaround).
import std/cgi

var rewriteCount {.global.} = 0

template rewriteSetTestData{setTestData(kv)}(kv: varargs[string]) =
  inc(rewriteCount)
  discard

setTestData("k1", "v1", "k2", "v2")
echo "rewriteCount=", rewriteCount
