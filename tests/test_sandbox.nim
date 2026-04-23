import std/[unittest, options]
import tripwire/[types, errors, timeline, sandbox, verify]

suite "sandbox":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "newVerifier defaults":
    let v = newVerifier("t1")
    check v.name == "t1"
    check v.active == true
    check v.generation == 0
    check v.timeline.nextSeq == 0

  test "push/pop verifier stack":
    let v = newVerifier()
    check currentVerifier() == nil
    discard pushVerifier(v)
    check currentVerifier() == v
    let popped = popVerifier()
    check popped == v
    check popped.active == false
    check popped.generation == 1
    check currentVerifier() == nil

  test "nested push/pop":
    let v1 = newVerifier("outer")
    let v2 = newVerifier("inner")
    discard pushVerifier(v1)
    discard pushVerifier(v2)
    check currentVerifier() == v2
    discard popVerifier()
    check currentVerifier() == v1
    discard popVerifier()

  test "sandbox: template runs body and verifies":
    ## Empty body: nothing to verify, should not raise.
    var ran = false
    sandbox:
      ran = true
    check ran

  test "sandbox: raises when mock registered but never consumed":
    expect UnusedMocksDefect:
      sandbox:
        let v = currentVerifier()
        let resp = MockResponse()
        let m = newMock("f", "fp", resp, (filename: "x.nim", line: 1, column: 0))
        registerMock(v, "p1", m)
