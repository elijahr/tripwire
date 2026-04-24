## tests/test_errors_facade.nim — Task 2.4 compile-time gate.
##
## Proves that the `tripwire` facade transitively re-exports the WI2
## thread-rejection defect types (`ChronosOnWorkerThreadDefect`,
## `NestedTripwireThreadDefect`) and the 2-arg `newPendingAsyncDefect`
## overload added in Task 2.3, via the existing `export errors` line
## in `src/tripwire.nim`.
##
## This file deliberately imports ONLY the facade (`import tripwire`)
## and NOT `tripwire/errors`. If a future refactor drops `errors` from
## the facade's re-export list (or stops re-exporting a specific
## symbol), this file fails at compile time, which is exactly the
## guardrail we want before WI3 (threads) and WI4 (async registry)
## land.
##
## Import convention matches `tests/test_self_three_guarantees.nim`:
## the `nimble test` task passes `--define:tripwireActive` and
## `--import:tripwire/auto`, so `import tripwire` resolves without
## tripping Defense 1. Do NOT `import std/unittest` separately — the
## facade re-exports the unittest backend (stripped of `test`/`suite`),
## and importing std/unittest alongside would create an ambiguous-call
## clash under the `-d:tripwireUnittest2` matrix cell.
import tripwire

suite "WI2 facade re-exports (Task 2.4)":
  test "ChronosOnWorkerThreadDefect visible through tripwire facade":
    let d = newChronosOnWorkerThreadDefect(1,
      (filename: "x.nim", line: 1, column: 1))
    check d of ChronosOnWorkerThreadDefect
    check d of TripwireDefect
    check d of Defect

  test "NestedTripwireThreadDefect visible through tripwire facade":
    let d = newNestedTripwireThreadDefect(1,
      (filename: "x.nim", line: 1, column: 1))
    check d of NestedTripwireThreadDefect
    check d of TripwireDefect
    check d of Defect

  test "newPendingAsyncDefect(msg, parent) overload visible through facade":
    let d = newPendingAsyncDefect("facade test", nil)
    check d of PendingAsyncDefect
    check d of TripwireDefect
    check d.parent == nil
