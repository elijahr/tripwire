import std/[unittest, tables, options, deques]
import tripwire/[types, errors, timeline, sandbox, verify]

suite "verifier":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "popMatchingMock returns none on empty queue":
    let v = newVerifier()
    check popMatchingMock(v, "p1", "f", "fp").isNone

  test "popMatchingMock head-FIFO on match":
    let v = newVerifier()
    let m = newMock("f", "fp", MockResponse(),
      (filename: "x.nim", line: 1, column: 0))
    registerMock(v, "p1", m)
    let got = popMatchingMock(v, "p1", "f", "fp")
    check got.isSome
    check got.get == m
    check popMatchingMock(v, "p1", "f", "fp").isNone

  test "popMatchingMock returns none on head mismatch (FIFO-strict)":
    let v = newVerifier()
    let m1 = newMock("f1", "fp1", MockResponse(),
      (filename: "x.nim", line: 1, column: 0))
    let m2 = newMock("f2", "fp2", MockResponse(),
      (filename: "x.nim", line: 2, column: 0))
    registerMock(v, "p1", m1)
    registerMock(v, "p1", m2)
    check popMatchingMock(v, "p1", "f2", "fp2").isNone  # head is f1

  test "popMatchingMock inAnyOrder scans full queue (regression)":
    let v = newVerifier()
    v.context.inAnyOrderActive = true
    let m1 = newMock("f1", "fp1", MockResponse(),
      (filename: "x.nim", line: 1, column: 0))
    let m2 = newMock("f2", "fp2", MockResponse(),
      (filename: "x.nim", line: 2, column: 0))
    registerMock(v, "p1", m1)
    registerMock(v, "p1", m2)
    let got = popMatchingMock(v, "p1", "f2", "fp2")
    check got.isSome
    check got.get == m2              # captured BEFORE deque mutation
    check v.mockQueues["p1"].mocks.len == 1
    check v.mockQueues["p1"].mocks.peekFirst() == m1

  test "verifyAll raises UnassertedInteractionsDefect first":
    let v = newVerifier("t1")
    let p = Plugin(name: "p1")
    discard v.timeline.record(p, "f", initOrderedTable[string, string](),
      nil, (file: "x", line: 1, column: 0))
    expect UnassertedInteractionsDefect:
      v.verifyAll()

  test "verifyAll raises UnusedMocksDefect when timeline clean":
    let v = newVerifier("t1")
    let m = newMock("f", "fp", MockResponse(),
      (filename: "x.nim", line: 1, column: 0))
    registerMock(v, "p1", m)
    expect UnusedMocksDefect:
      v.verifyAll()

  test "fingerprintOf is deterministic":
    let fp1 = fingerprintOf("f", @["1", "2"])
    let fp2 = fingerprintOf("f", @["1", "2"])
    check fp1 == fp2
    check fp1 != fingerprintOf("f", @["1", "3"])
