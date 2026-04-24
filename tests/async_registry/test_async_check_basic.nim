## tests/async_registry/test_async_check_basic.nim — Task 4.4 (E3; M2).
##
## Exercises the fundamental `asyncCheckInSandbox` happy path: a Future
## spawned inside `sandbox:` awaits, completes DURING `drainPendingAsync`,
## and the Future body's TRM fires against the still-active verifier.
## After drain, the mock the Future authorized is consumed, the timeline
## interaction is asserted, and `sandbox:` exits cleanly (no
## `PendingAsyncDefect`, no `UnusedMocksDefect`).
##
## Maps impl plan Task 4.4 (file `2026-04-23-tripwire-v0.2-impl.md` lines
## 793-806) and design §4.8 row E3.
##
## Pattern: module-scope `mockable` + wrapper proc + `{.async.}` worker,
## modeled on `tests/threads/test_tripwire_thread_basic.nim` and
## `tests/test_mock_expect.nim` (see those files for the full
## unittest-dirty-template TRM gotcha rationale).
##
## RED signal chosen: wrong-arg mock expectation. The RED version of
## this file registers `mock.expect computeThing(99): respond value: 99`
## while the async body calls `callComputeThing(7)`. MockPlugin's
## passthrough lets the (7) call fall through to the real impl
## (`x * 2` → 14), so the Future resolves to 14 (NOT the mocked 99).
## But the expectation for (99) is never consumed, and `verifyAll` at
## `sandbox:` exit raises `UnusedMocksDefect`. Flipping the expect arg
## to `7` turns the test GREEN (the TRM intercepts, consumes the mock,
## returns 99, and verifyAll sees a clean verifier).
## This signal was chosen over "delete the drain call" because deletion
## would leak a pending op to subsequent tests in an aggregated suite
## and would also trigger multiple overlapping failures — the wrong-arg
## approach produces a single, unambiguous `UnusedMocksDefect`.
##
## Respond value 99 (not 14) is deliberately chosen to be DISTINCT from
## the real impl's output `computeThing(7) = 14`. If the TRM consumed
## the mock but then silently fell through to the real impl, `fut.read`
## would be 14 and the test would pass for the wrong reason. Using 99
## makes "mock respond returned" vs "real impl output" directly
## distinguishable on the Future result.
##
## Consumer-import requirement (design §4.1 line 724): modules that
## invoke `asyncCheckInSandbox` MUST also `import std/asyncdispatch`
## so that `Future[T]` resolves at the call site, even though the
## template `bind`s `asyncCheck` from the library module.
import std/[unittest, asyncdispatch, options, tables, deques]
import tripwire/[types, errors, timeline, sandbox, verify, intercept,
                async_registry, macros as nfmacros]
import tripwire/plugins/mock

# User proc we intend to mock. Real impl is `x * 2`.
proc computeThing(x: int): int =
  x * 2   # real impl; TRM intercepts this when a matching mock is registered

# Module-scope TRM emission. Dummy arg (0) only provides arity/type for
# the pattern's formal params; the value is not used at runtime.
mockable(computeThing(0))

# Wrapper proc — calling the mocked proc from here (not directly from the
# async body's statement list) matches the pattern in test_mock_expect.nim
# and keeps the TRM firing reliably in Nim 2.2.6.
#
# `{.gcsafe.}` cast: the TRM expansion references `mockPluginInstance`
# (an immutable module-scope `let` in tripwire/plugins/mock.nim) and
# verifier state the plugin guards. Async worker procs are inferred
# `gcsafe` by the compiler under `--threads:on`; the cast mirrors the
# thread-tests pattern and is safe because the touched state is either
# immutable or the shared `ref Verifier`.
proc callComputeThing(x: int): int {.gcsafe.} =
  {.cast(gcsafe).}:
    computeThing(x)

# Async worker: yields via sleepAsync so the Future is still pending when
# `asyncCheckInSandbox` registers it. The TRM fires after the sleep,
# during the drain poll loop, and the interaction lands on the verifier
# that was current at spawn time.
proc asyncWorker(): Future[int] {.async.} =
  await sleepAsync(20)   # yield so drain has to poll at least once
  return callComputeThing(7)

suite "asyncCheckInSandbox: basic happy path":
  setup:
    # Drain any stack left by earlier tests so this test starts clean.
    while currentVerifier() != nil:
      discard popVerifier()

  test "Future completes during drain; mock is consumed; sandbox exits cleanly":
    sandbox:
      # Pre-authorize the mock BEFORE spawning the Future. The async
      # body's TRM fires for computeThing(7) during the drain poll,
      # matches this expectation, consumes the mock, and resolves the
      # Future to 99 (the mock's respond value — DISTINCT from the
      # real impl's `7 * 2 = 14` so the assertion below can't pass on
      # silent passthrough).
      mock.expect computeThing(7):
        respond value: 99

      let v = currentVerifier()
      let fut = asyncWorker()
      asyncCheckInSandbox(fut)

      # Explicit drain (Task 4.6 wiring for integration_unittest.test is
      # not landed; this call is the v0.2 workaround until the wrapping
      # `test:` template drains automatically).
      drainPendingAsync(currentVerifier())

      # Post-drain: Future must be resolved and carry the MOCK's respond
      # value (99), NOT the real impl's output (14). This assertion
      # distinguishes "TRM intercepted + mock consumed" from "mock
      # consumed but passthrough still ran real impl" (a latent bug
      # shape that would produce 14 instead of 99).
      check fut.finished
      check fut.read == 99

      # Timeline must contain exactly the one TRM fire (for (7)).
      check v.timeline.entries.len == 1

      # Consume the interaction so `verifyAll` at sandbox exit sees a
      # clean timeline (otherwise it would raise
      # `UnassertedInteractionDefect`). Mirrors the consumption step in
      # test_mock_expect.nim and test_tripwire_thread_basic.nim.
      v.timeline.markAsserted(v.timeline.entries[0])
    # sandbox exit runs verifyAll: the mock for (7) was consumed, the
    # timeline entry was marked asserted, and the futureRegistry was
    # cleared by the drain. No defect raised.
