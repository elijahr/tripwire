## tests/threads/test_refc_threads_rejected.nim — Task 3.9 negative
## build probe for F2 (refc + threads rejected at compile time).
##
## This file is NEVER intended to be RUN. It is a compile-time probe
## driven by the matrix cell in tripwire.nimble's `task test`. That
## subtask invokes (via nimscript's `gorgeEx`):
##
##   nim check --gc:refc --threads:on -d:tripwireActive \
##             tests/threads/test_refc_threads_rejected.nim
##
## and asserts the build FAILS with exit code != 0 AND the error output
## contains `tripwireThread requires --gc:orc`. That error is emitted by
## the `{.error.}` pragma at `src/tripwire/threads.nim` lines 23-26,
## which fires under `when defined(gcRefc) and compileOption("threads")`.
## `nim check` is used (rather than `nim c`) because the front-end
## type-check phase is enough to trip the `{.error.}` pragma — no C
## codegen is needed, which makes the negative-build subtask faster and
## leaves no build artifacts to clean up.
##
## The import below is enough to trip the guard: `tripwire/threads`
## evaluates its top-level `when` blocks at module-load time, so merely
## importing it under refc+threads triggers the compile-time error.
## No runtime code is needed; we do NOT emit anything callable.
##
## Under arc+threads (the happy path), this file compiles cleanly but
## does nothing useful — `when false` branches skip the usage site, and
## the top-level `import` is the only effect. That is intentional:
## arc+threads compilation succeeding is part of the contract (confirms
## the `{.error.}` is scoped to refc only, not a blanket threads-off
## guard that would block the arc+threads matrix cell too).
##
## Design citations:
##   - §8.1: supported GCs clause — refc+threads is rejected; arc and
##     orc are co-equal supported.
##   - §3.6 F2: refc + threads rejected at compile time with a loud
##     error message pointing at the v0.3 roadmap for eventual lift.
##
## Metric: M-matrix (matrix cell #7 orc+threads required-green; refc+
## threads rejected-at-compile-time via this negative-build probe).

import tripwire/threads

# `when false` ensures the grandchild-spawn probe's body never
# type-checks against the real withTripwireThread surface — we do NOT
# want this file to exercise runtime threading behavior. The sole
# purpose of this source is to force a compile-time evaluation of
# `tripwire/threads`'s top-level `when` guards. The import above is
# sufficient for that; the `when false` block below keeps the import
# non-vacuous (no "unused import" warning) without emitting runnable
# code.
when false:
  discard withTripwireThread
