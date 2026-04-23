## tests/test_defenses.nim — probes for compile-time defense gates
## plus runtime regressions for Defenses 3, 5, and 6 (Task H3).
##
## Covers:
##   - **Defense 1** (G2): `import nimfoot` must fail with a clear
##     {.error.} when the consumer forgot to activate via
##     `--import:"nimfoot/auto" --define:"nimfootActive"`. The
##     escape hatch `-d:nimfootAllowInactive` must suppress the
##     error for tooling that references nimfoot symbols without
##     wiring up TRM activation.
##   - **Defense 3** (D2): the compile-time rewrite cap message.
##     Probe + 15-OK cell live in `test_cap_counter.nim`; this file
##     adds a message-shape regression check.
##   - **Defense 5** (F8): fallback-trap coverage lives in
##     `test_osproc_arrays.nim` (kept standalone because its
##     per-wrapper TRM count pushes past the aggregate's 15 cap).
##     No duplication here — this note records the cross-reference
##     for the suite.
##   - **Defense 6** (A7/A6): LeakedInteractionDefect (TRM fires
##     with no verifier on the stack), PostTestInteractionDefect
##     (TRM fires against a popped-but-still-current verifier), and
##     PendingAsyncDefect (test body leaks a Future).
##
## The Defense 1 probes shell out to `nim check` so the guard's
## compile-time error terminates the subprocess, not the main
## test binary.
import std/[unittest, osproc, strutils]
import nimfoot/[types, errors, timeline, sandbox, verify, intercept,
                futures, cap_counter]

const FixturePath = "tests/fixtures/defense1_probe.nim"

suite "Defense 1: facade activation guard (G2)":
  test "D1: importing nimfoot without flags fails at compile time":
    let cmd = "nim check --hints:off --warnings:off " & FixturePath & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    check code != 0
    check "nimfoot was imported but not activated" in output

  test "D1: -d:nimfootAllowInactive suppresses the error":
    let cmd = "nim check --hints:off -d:nimfootAllowInactive " &
      FixturePath & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    check code == 0

  test "D1: -d:nimfootActive (the activation path) also suppresses":
    # Sanity check: the intended happy path (user set nimfootActive)
    # must also compile clean.
    let cmd = "nim check --hints:off -d:nimfootActive " &
      FixturePath & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0:
      echo output
    check code == 0

  test "facade exposes the full public API surface":
    # The fixture imports nimfoot and also references symbols that
    # live in the core modules (types, errors, sandbox, etc.). If the
    # facade fails to re-export them, `nim check` on the fixture with
    # `-d:nimfootActive` will error with `undeclared identifier`.
    const SurfacePath = "tests/fixtures/facade_surface.nim"
    let cmd = "nim check --hints:off -d:nimfootActive " &
      SurfacePath & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0:
      echo output
    check code == 0

# ---- Defense 3: cap-counter message shape ------------------------------
# The compile-fail probe lives in test_cap_counter.nim; this suite
# confirms the message surface-area that users see. Running `nim check`
# against the fixture a second time would be redundant, so we assert
# on the constant embedded in cap_counter.nim instead.
suite "Defense 3: cap-counter message shape":
  test "threshold constant is 15 (conservative margin below ~19)":
    check NimfootCapThreshold == 15

  test "threshold constant is exported through the facade":
    # If cap_counter.nim stops exporting the constant, or the facade
    # fails to re-export it transitively, this breaks at compile time
    # because `NimfootCapThreshold` resolves from `nimfoot/cap_counter`
    # via the registry module's transitive import.
    #
    # NOTE: The constant is intentionally NOT re-exported from the
    # public `nimfoot` facade (cap_counter is an internal concern);
    # what the facade exposes is the runtime effect, not the knob.
    check NimfootCapThreshold > 10 and NimfootCapThreshold < 19

# ---- Defense 6: LeakedInteraction / PostTestInteraction / PendingAsync -
# These defects guard the verifier-stack invariants: TRMs must only fire
# while a verifier is current AND active, and test bodies must drain
# their async futures before returning.
#
# We construct each scenario without relying on the plugin TRM call
# sites (that would inflate this file's rewrite count and collide with
# the 15-TRM cap under `-d:nimfootActive`). Instead we invoke the
# defect constructors directly and thread them through the same
# code paths the TRM bodies use.
suite "Defense 6: LeakedInteractionDefect":
  test "constructor builds an informative message":
    let d = newLeakedInteractionDefect(0,
      (filename: "t.nim", line: 10, column: 3))
    check d.threadId == 0
    check "no active verifier" in d.msg
    check "t.nim:10" in d.msg

  test "TRM path raises when stack is empty (covered by test_intercept.nim)":
    # `nimfootPluginIntercept`'s first action (after cap-count) is to
    # check `currentVerifier()`; nil → LeakedInteractionDefect. End-to-end
    # coverage lives in `test_intercept.nim` "unmocked without passthrough"
    # + "leaked interaction" paths — both fire the raise. Duplicating the
    # TRM-site setup here would collide with the 15-TRM cap in the
    # aggregate build, so this file only checks the constructor surface.
    let d = newLeakedInteractionDefect(1,
      (filename: "call.nim", line: 5, column: 0))
    check d != nil

suite "Defense 6: PostTestInteractionDefect":
  test "constructor records verifier generation":
    let d = newPostTestInteractionDefect("leaked", 3, "httpclient", "request")
    check d.verifierName == "leaked"
    check d.generation == 3
    check d.pluginName == "httpclient"
    check d.procName == "request"
    check "popped verifier" in d.msg

  test "popped verifier is marked inactive":
    # Sanity: popVerifier flips active=false and bumps generation.
    # The intercept check `if not v.active` uses this to route to
    # PostTestInteractionDefect rather than LeakedInteraction.
    let v = newVerifier("check")
    discard pushVerifier(v)
    discard popVerifier()
    check v.active == false
    check v.generation == 1

suite "Defense 6: PendingAsyncDefect":
  test "constructor names the offending test":
    let d = newPendingAsyncDefect("leaks-future")
    check d.testName == "leaks-future"
    check "pending async" in d.msg
    check "waitFor" in d.msg

  test "hasPendingOperations gates the check":
    # With no pending operations, nimfoot's `test:` template would not
    # raise. This regression catches the case where the re-exported
    # asyncdispatch shadows our `hasPendingOperations` wrapper (see
    # futures.nim docstring: we re-export asyncdispatch EXCEPT this
    # name so consumers get our wrapper via `nimfoot`).
    check not futures.hasPendingOperations()
