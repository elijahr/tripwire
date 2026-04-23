## tripwire/cap_counter.nim — Defense 3 compile-time rewrite cap.
##
## Nim's term-rewriting-macros engine silently drops rewrites past ~19 per
## hloBody. Past that threshold, a TRM `expect`-ed call simply runs its
## original body instead of the mocked one — the test passes, the mock
## is never consumed, and `verifyAll` raises `UnusedMocksDefect` or, worse,
## a real network call escapes.
##
## Defense 3 enforces a conservative cap of 15 rewrites per compilation
## unit so users hit a loud compile error well before the silent threshold.
## The counter is global to the compilation (declared `{.compileTime.}`);
## `sandbox:` / `test:` sub-blocks reset the per-hloBody rewrite count
## in their own lexical proc, which is the documented escape hatch for
## tests that need more than 15 mock calls.
##
## Implementation note: we use a macro that calls `std/macros.error` at
## expansion time rather than `when` + `{.error.}` inside a `static:`
## block. Nim's `when` is evaluated during sem-check before the enclosing
## `static:` block's mutations to `{.compileTime.}` variables are visible
## to the branch predictor, so `when nfRewriteCount > N` silently fails
## to trip even after `inc` has run. Calling `macros.error` from a macro
## bypasses that phase ordering — the macro runs at expansion time with
## the up-to-date counter value.

import std/macros

const TripwireCapThreshold* = 15
  ## Maximum rewrites allowed in one compilation unit. Set conservatively
  ## below Nim's ~19 internal cap to leave headroom for Nim updates.

var nfRewriteCount {.compileTime.} = 0

macro tripwireCountRewrite*(): untyped =
  ## Plugin TRM bodies call this unconditionally. At expansion time it
  ## increments the per-compilation-unit counter; if the threshold is
  ## exceeded `macros.error` aborts compilation with a message that
  ## directs the user to split the test.
  inc(nfRewriteCount)
  if nfRewriteCount > TripwireCapThreshold:
    error("tripwire: more than " & $TripwireCapThreshold &
      " TRM rewrites in a single compilation unit. Nim's rewrite " &
      "engine silently drops rewrites past ~19. Split the test with " &
      "`sandbox:` sub-blocks or refactor into smaller helpers.")
  result = newStmtList()
