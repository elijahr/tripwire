## Target 6: std/strutils.parseInt(s: string): int — control case.
## Boring target: should match cleanly if the TRM machinery works at all
## against stdlib.
import std/strutils

var rewriteCount {.global.} = 0

template rewriteParseInt{parseInt(s)}(s: string): int =
  inc(rewriteCount)
  777  # sentinel, obviously not a real parse

let v = parseInt("123")
echo "value=", v, " rewriteCount=", rewriteCount
