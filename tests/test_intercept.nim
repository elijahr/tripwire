import std/[unittest, tables, options]
import nimfoot/[types, errors, timeline, sandbox, verify, intercept]

# ---- Test plugin ---------------------------------------------------------
type
  TestIntPlugin* = ref object of Plugin
  TestIntResp* = ref object of MockResponse
    val*: int

method realize*(r: TestIntResp): int = r.val

method supportsPassthrough*(p: TestIntPlugin): bool = true
method passthroughFor*(p: TestIntPlugin, procName: string): bool =
  procName == "spyProc"

let testIntPlugin* = TestIntPlugin(name: "testint", enabled: true)

# ---- Wrappers that use the combinator ------------------------------------
# We simulate a TRM body by wrapping nimfootInterceptBody in a proc that
# calls it on known args. Real plugins have this body inside a TRM
# template; for unit-testing the combinator, a regular proc suffices.
proc interceptedAdd(a, b: int): int =
  nimfootInterceptBody(testIntPlugin, "interceptedAdd",
    fingerprintOf("interceptedAdd", @[$a, $b]),
    TestIntResp):
    {.noRewrite.}:
      a + b

proc spyProc(x: int): int =
  nimfootInterceptBody(testIntPlugin, "spyProc",
    fingerprintOf("spyProc", @[$x]),
    TestIntResp):
    {.noRewrite.}:
      x * 10

suite "intercept":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "no verifier -> LeakedInteractionDefect":
    expect LeakedInteractionDefect:
      discard interceptedAdd(1, 2)

  test "popped verifier -> PostTestInteractionDefect":
    let v = newVerifier("t")
    discard pushVerifier(v)
    discard popVerifier()            # v.active now false
    discard pushVerifier(v)          # push again to become current
    expect PostTestInteractionDefect:
      discard interceptedAdd(1, 2)
    discard popVerifier()

  test "matched mock returns realized value":
    sandbox:
      let v = currentVerifier()
      let m = newMock("interceptedAdd",
        fingerprintOf("interceptedAdd", @["1", "2"]),
        TestIntResp(val: 42),
        (filename: "x.nim", line: 1, column: 0))
      registerMock(v, "testint", m)
      check interceptedAdd(1, 2) == 42
      # Must assert the interaction or verifyAll raises Unasserted.
      v.timeline.markAsserted(v.timeline.entries[0])

  test "unmocked without passthrough -> UnmockedInteractionDefect":
    let v = newVerifier("t")
    discard pushVerifier(v)
    try:
      expect UnmockedInteractionDefect:
        discard interceptedAdd(1, 2)
    finally:
      discard popVerifier()

  test "unmocked WITH passthrough -> spyBody runs":
    let v = newVerifier("t")
    discard pushVerifier(v)
    try:
      # spyProc is in passthroughFor, interceptedAdd is not.
      check spyProc(5) == 50
      # Timeline records the call even in passthrough mode.
      check v.timeline.entries.len == 1
      check v.timeline.entries[0].procName == "spyProc"
      v.timeline.markAsserted(v.timeline.entries[0])
    finally:
      discard popVerifier()
