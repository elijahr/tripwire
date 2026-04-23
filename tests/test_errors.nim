import std/[unittest, tables, strutils]
import tripwire/[types, errors]

suite "errors":
  test "UnmockedInteractionDefect inherits from TripwireDefect":
    let e = newUnmockedInteractionDefect("httpclient", "get", "fp",
      (file: "t.nim", line: 1, column: 1))
    check e of UnmockedInteractionDefect
    check e of TripwireDefect
    check e of Defect
    check e.pluginName == "httpclient"
    check FFIScopeFooter in e.msg

  test "UnassertedInteractionsDefect carries interactions":
    let e = newUnassertedInteractionsDefect("test1", @[])
    check e.verifierName == "test1"
    check e.interactions.len == 0
    check FFIScopeFooter in e.msg

  test "PendingAsyncDefect carries test name":
    let e = newPendingAsyncDefect("test_x")
    check e.testName == "test_x"
    check e of TripwireDefect

  test "LeakedInteractionDefect carries threadId":
    let e = newLeakedInteractionDefect(42,
      (filename: "x.nim", line: 5, column: 2))
    check e.threadId == 42

  test "PostTestInteractionDefect carries generation":
    let e = newPostTestInteractionDefect("t", 3, "p", "proc1")
    check e.generation == 3

  test "AssertionInsideSandboxError is CatchableError, not Defect":
    let e = new AssertionInsideSandboxError
    check e of CatchableError
    check not (e of Defect)

  test "TripwireDefect cannot be caught by except CatchableError":
    ## Sanity check of Defense 4 — verifies the hierarchy choice.
    var caught = false
    try:
      raise newPendingAsyncDefect("t")
    except CatchableError:
      caught = true
    except Defect:
      caught = false
    check caught == false
