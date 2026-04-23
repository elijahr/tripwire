## tests/test_integration_unittest.nim — E1 integration test.
##
## Exercises `tripwire/integration_unittest` (std/unittest backend): the
## `test:` template wraps a std/unittest test body with a verifier
## lifecycle (push on entry, verifyAll on teardown, addExitProc wire-up).
##
## Self-hosting note: we must NOT use tripwire's `test:` at the outer
## level — we're the module testing it. Use `std/unittest` directly for
## the outer suite, and invoke tripwire's `test:` as a nested construct
## inside the body.
##
## Backend swallow caveat: `std/unittest.test` catches all exceptions and
## only reports them via the process exit code. So when we need to
## assert that the `test:` lifecycle actually RAISES a tripwire defect
## (rather than checking that the program exit code flipped to 1), we
## invoke the lifecycle steps directly from the outer `std_ut.test`
## body. The happy path is still exercised through the real nested
## `test:` form below.
##
## Backend gating: this file is a no-op when compiled with
## `-d:tripwireUnittest2` because `integration_unittest` then swaps its
## backend to unittest2, and importing both unittest frameworks in the
## same module collides on their shared identifiers (TestStatus, etc.).
## The unittest2 matrix cell is covered by `test_integration_unittest2.nim`.
when not defined(tripwireUnittest2):
  import std/[unittest as std_ut, tables, options]
  import tripwire/[types, errors, timeline, sandbox, verify, intercept,
                  integration_unittest]

  # ---- Local test plugin ----
  # The `it` plugin is a minimal shim so we can register a mock and
  # record an interaction without pulling in any "real" plugin.
  type
    ItPlugin = ref object of Plugin
    ItResp = ref object of MockResponse
      v: int
  method realize(r: ItResp): int = r.v

  let itPlugin = ItPlugin(name: "it", enabled: true)

  proc itCall(a: int): int =
    tripwireInterceptBody(itPlugin, "itCall",
      fingerprintOf("itCall", @[$a]),
      ItResp):
      {.noRewrite.}:
        a

  std_ut.suite "integration_unittest":
    std_ut.test "tripwire test: registers verifier, body runs, teardown verifies":
      # Happy path through the real nested `test:` form — verifier is
      # pushed, body runs, timeline entry is asserted, teardown verifyAll
      # passes. An outer `ran` flag confirms the body executed.
      var ran = false
      test "inner-happy":
        let v = currentVerifier()
        std_ut.check v != nil
        let m = newMock("itCall", fingerprintOf("itCall", @["5"]),
          ItResp(v: 42),
          (filename: "t.nim", line: 1, column: 0))
        registerMock(v, "it", m)
        std_ut.check itCall(5) == 42
        v.timeline.markAsserted(v.timeline.entries[0])
        ran = true
      std_ut.check ran

    std_ut.test "tripwire test lifecycle raises UnusedMocksDefect when mock unconsumed":
      # Direct invocation of the `test:` lifecycle so the defect escapes
      # rather than being absorbed by `backend.test`'s blanket handler.
      # Mirrors what the template expands to, one-to-one.
      std_ut.expect UnusedMocksDefect:
        let nfV = pushVerifier(newVerifier("inner-unused-mock"))
        try:
          let m = newMock("itCall", "x", ItResp(v: 1),
            (filename: "t.nim", line: 1, column: 0))
          registerMock(nfV, "it", m)
          # body ends without consuming the mock
        finally:
          discard popVerifier()
          nfV.verifyAll()  # raises UnusedMocksDefect

    std_ut.test "tripwire test lifecycle raises UnassertedInteractionsDefect":
      # Same direct invocation, this time with a consumed mock but no
      # markAsserted -> UnassertedInteractionsDefect.
      std_ut.expect UnassertedInteractionsDefect:
        let nfV = pushVerifier(newVerifier("inner-unasserted"))
        try:
          let m = newMock("itCall", fingerprintOf("itCall", @["7"]),
            ItResp(v: 99),
            (filename: "t.nim", line: 1, column: 0))
          registerMock(nfV, "it", m)
          std_ut.check itCall(7) == 99
          # no markAsserted -> verifyAll raises
        finally:
          discard popVerifier()
          nfV.verifyAll()

    std_ut.test "verifyAllOnExit drains leaked verifier without raising":
      # addExitProc semantics: verifyAllOnExit must not re-raise (exit
      # procs may not raise). It should swallow the defect and print to
      # stderr instead. We simulate a leak by leaving a verifier on the
      # stack with an unused mock, call verifyAllOnExit directly, and
      # check the stack was drained.
      let nfV = pushVerifier(newVerifier("leaked"))
      let m = newMock("itCall", "x", ItResp(v: 1),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(nfV, "it", m)
      std_ut.check verifierStack.len == 1
      verifyAllOnExit()   # must not raise
      std_ut.check verifierStack.len == 0

    std_ut.test "backend alias exposes std/unittest under default build":
      # Under the default (no -d:tripwireUnittest2) the backend alias
      # resolves to std/unittest. Exercised here; the unittest2 parity
      # test lives in tests/test_integration_unittest2.nim.
      std_ut.check backendName == "std/unittest"
