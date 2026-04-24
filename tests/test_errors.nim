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

suite "WI2 defect types (design §2.3, §3.6)":
  test "ChronosOnWorkerThreadDefect construction":
    let d = newChronosOnWorkerThreadDefect(42,
      (filename: "x.nim", line: 10, column: 5))
    check d of ChronosOnWorkerThreadDefect
    check d of TripwireDefect
    check d of Defect
    check "tripwireThread rejected" in d.msg
    check "chronos on worker thread" in d.msg
    check "on thread 42" in d.msg
    check "x.nim:10" in d.msg
    check FFIScopeFooter in d.msg

  test "NestedTripwireThreadDefect construction":
    let d = newNestedTripwireThreadDefect(7,
      (filename: "nested.nim", line: 99, column: 3))
    check d of NestedTripwireThreadDefect
    check d of TripwireDefect
    check d of Defect
    check "tripwireThread rejected" in d.msg
    check "nested tripwire thread" in d.msg
    check "on thread 7" in d.msg
    check "nested.nim:99" in d.msg
    check FFIScopeFooter in d.msg

  test "Chronos and Nested defects have distinct reason strings":
    ## Guards against copy-paste swap of the reason portion.
    let c = newChronosOnWorkerThreadDefect(1,
      (filename: "a.nim", line: 1, column: 1))
    let n = newNestedTripwireThreadDefect(1,
      (filename: "a.nim", line: 1, column: 1))
    check "chronos on worker thread" in c.msg
    check "nested tripwire thread" notin c.msg
    check "nested tripwire thread" in n.msg
    check "chronos on worker thread" notin n.msg

  test "newPendingAsyncDefect(msg, parent) overload — nil parent":
    let d = newPendingAsyncDefect("custom drain-loop msg", nil)
    check d of PendingAsyncDefect
    check d of TripwireDefect
    check "custom drain-loop msg" in d.msg
    check d.msg.endsWith(FFIScopeFooter)
    check d.parent == nil

  test "newPendingAsyncDefect(msg, parent) overload — carries parent":
    let p: ref Exception = newException(IOError, "upstream")
    let d = newPendingAsyncDefect("drain failed", p)
    check d of PendingAsyncDefect
    check "drain failed" in d.msg
    check d.msg.endsWith(FFIScopeFooter)
    check d.parent == p

  test "newPendingAsyncDefect(testName) one-arg form unchanged (regression)":
    ## Pins the v0.1 message format byte-for-byte. Any change to the
    ## one-arg form MUST fail this assertion.
    let d = newPendingAsyncDefect("my_test_case")
    let expected = "test 'my_test_case' ended with pending async operations." &
      "\nUse `waitFor` to drain futures, or -d:tripwireAllowPendingAsync to" &
      " suppress." & FFIScopeFooter
    check d.msg == expected
    check d.testName == "my_test_case"
