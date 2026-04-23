## Q3: Does a TRM fire on `await` itself?
##
## `await f` is sugar the async transform expands. This TRM attempts to
## match the `await(f)` call shape on a Future[string]. If successful,
## awaiting a concrete Future[string] inside an async proc should increment
## awaitRewrites and substitute the body "intercepted await".
import std/asyncdispatch

var awaitRewrites* = 0

template rewriteAwait*{await(f)}(f: Future[string]): string =
  inc(awaitRewrites)
  "intercepted await"

proc makeFuture(): Future[string] =
  result = newFuture[string]("makeFuture")
  result.complete("real future value")

proc consumer(): Future[string] {.async.} =
  let f = makeFuture()
  let v = await f
  return v

let r = waitFor consumer()
echo "result=", r
echo "awaitRewrites=", awaitRewrites
