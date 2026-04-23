## tests/test_async_asyncdispatch.nim — C1 acceptance test for
## asyncdispatch branch of tripwire/futures.
import std/unittest
import tripwire/futures
# `tripwire/futures` re-exports `std/asyncdispatch` EXCEPT
# `hasPendingOperations` (the tripwire wrapper intentionally shadows it
# to OR in chronos's count when compiled with `-d:chronos
# -d:chronosFutureTracking`). So `waitFor`, `Future`, `newException`,
# etc. come through unchanged; `hasPendingOperations` resolves to the
# tripwire wrapper without ambiguity.

suite "async asyncdispatch":
  test "makeCompletedFuture yields the value":
    let f = makeCompletedFuture[int](42, "test")
    check waitFor(f) == 42

  test "makeFailedFuture raises on await":
    let f = makeFailedFuture[int](newException(ValueError, "nope"),
                                  "test_fail")
    expect ValueError:
      discard waitFor(f)

  test "hasPendingOperations false after drain":
    ## Having just drained both completed and failed futures, the
    ## dispatcher should report no outstanding callbacks.
    check hasPendingOperations() == false
