## tests/test_async_chronos.nim — C2 chronos overlay test.
##
## Validates that nimfoot/futures.nim's chronos branch (the
## `makeCompletedFutureChronos` / `makeFailedFutureChronos` procs)
## returns actual `chronos.Future[T]` values that behave correctly
## under chronos's own `waitFor`.
##
## Gated at module scope by `when defined(chronos)` so the file is
## a no-op when compiled without `-d:chronos`. Consequently the default
## `nimble test` cell and all non-chronos matrix cells silently skip
## this file, and the optional chronos cell (set via
## `NIMFOOT_TEST_CHRONOS=1` or `-d:chronos`) exercises it.
when defined(chronos):
  import std/unittest
  import chronos
  import nimfoot/futures

  suite "async chronos":
    test "makeCompletedFutureChronos returns a chronos Future":
      ## Deterministic RED signal: if futures.nim's chronos branch is
      ## missing or wires to the wrong type (e.g., returning
      ## `asyncdispatch.Future[int]`), this call either fails to
      ## compile or the `is chronos.Future[int]` check returns false.
      let f = makeCompletedFutureChronos[int](42, "cc_test")
      check f is chronos.Future[int]
      check waitFor(f) == 42

    test "makeFailedFutureChronos raises on await":
      let f = makeFailedFutureChronos[int](
        newException(ValueError, "nope"), "cc_fail")
      expect ValueError:
        discard waitFor(f)
else:
  # No-op when chronos isn't compiled in. The aggregator at
  # tests/all_tests.nim imports this file unconditionally; the guard
  # keeps the file empty (no imports, no tests) in default builds.
  discard
