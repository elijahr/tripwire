## Variant TRM module probing different generic TRM syntaxes.
import common

var rewriteCountGen* {.global.} = 0

## Variant C: SomeInteger constraint on non-generic-looking TRM signature.
template rewriteGenC*{targetGeneric(a, b)}(a, b: SomeInteger): SomeInteger =
  inc(rewriteCountGen)
  a + b + 1000
