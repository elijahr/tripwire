import std/unittest
import tripwire/[types, errors, timeline, sandbox, verify, context]

suite "context":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "inAssertBlock raises AssertionInsideSandboxError when sandbox active":
    expect AssertionInsideSandboxError:
      sandbox:
        inAssertBlock:
          discard  # body runs under active sandbox → raise

  test "inAssertBlock does NOT raise after sandbox teardown":
    # With no active verifier, the guard passes through.
    inAssertBlock:
      discard  # no exception expected

  test "inAnyOrder sets context flag":
    sandbox:
      let v = currentVerifier()
      check v.context.inAnyOrderActive == false
      inAnyOrder:
        check v.context.inAnyOrderActive == true
      check v.context.inAnyOrderActive == false

  test "inAnyOrder restores on exception":
    sandbox:
      let v = currentVerifier()
      try:
        inAnyOrder:
          raise newException(ValueError, "boom")
      except ValueError:
        discard
      check v.context.inAnyOrderActive == false
