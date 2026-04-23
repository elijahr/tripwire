## Target 9: std/streams.write[T](s: Stream, x: T) — generic proc.
## Per prior spike finding, a concrete-int TRM should match a T=int
## instantiation. Use newStringStream to avoid real I/O.
import std/streams

var rewriteCount {.global.} = 0

template rewriteWrite{write(s, x)}(s: Stream, x: int) =
  inc(rewriteCount)
  discard

let ss = newStringStream("")
ss.write(42)
echo "rewriteCount=", rewriteCount
