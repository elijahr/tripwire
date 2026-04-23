## The TRM module — this is what `--import:nimfoot_auto` would inject everywhere.
import common

var rewriteCount* {.global.} = 0
var rewriteCountGeneric* {.global.} = 0

## Non-generic TRM for the concrete (int, int) signature.
## Body returns `a + b + 1000` — observable, and bypasses re-matching `target`.
template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  a + b + 1000

## NOTE: a generic TRM with `[T]` on the template (e.g.
## `template foo*{targetGeneric(a, b)}[T](a, b: T): T = ...`) crashes
## the Nim 2.2.6 compiler with SIGSEGV during sem. Use a concrete
## or `SomeInteger`-constrained signature instead.
template rewriteTargetGeneric*{targetGeneric(a, b)}(a, b: int): int =
  inc(rewriteCountGeneric)
  a + b + 1000

## Sentinel symbol: if `--import:nimfoot_auto` truly injects into every unit,
## any unit should be able to reference `nimfoot_auto_sentinel` without
## importing us explicitly.
const nimfoot_auto_sentinel* = 42
