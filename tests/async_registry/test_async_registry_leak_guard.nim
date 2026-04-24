## tests/async_registry/test_async_registry_leak_guard.nim —
## Task 4.1 RED test. Verifies that invoking
## `asyncCheckInSandbox` with no active verifier on the stack
## raises `LeakedInteractionDefect` (design §4.1 lines 568-569,
## impl plan Task 4.1 acceptance criteria).
##
## Consumer-import requirement (impl plan line 724): modules that
## invoke `asyncCheckInSandbox` MUST also `import std/asyncdispatch`
## so that `Future[T]` resolves at the call site, even though the
## template `bind`s `asyncCheck` from the library module.
import std/[unittest, asyncdispatch]
import tripwire/[sandbox, errors, async_registry]

suite "async_registry leak guard":
  setup:
    # Drain any verifiers left by earlier tests so this test runs
    # with an empty stack — `asyncCheckInSandbox` must then see
    # `currentVerifier() == nil` and raise.
    while currentVerifier() != nil:
      discard popVerifier()

  test "asyncCheckInSandbox outside sandbox raises LeakedInteractionDefect":
    let fut = newFuture[int]("test_async_registry_leak_guard")
    fut.complete(7)  # completed so asyncCheck would be harmless if ever reached
    expect LeakedInteractionDefect:
      asyncCheckInSandbox(fut)
