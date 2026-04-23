## tests/test_integration_unittest2.nim — E2 compile-gate for the
## unittest2 backend of `tripwire/integration_unittest`.
##
## Gated entirely by `when defined(tripwireUnittest2)`. Without that
## define, the file is a no-op that imports nothing — so the default
## `nimble test` cell (which targets std/unittest) doesn't need
## unittest2 in the env to compile. Under `-d:tripwireUnittest2`, the
## same lifecycle assertions as E1 are re-run against unittest2 to
## prove the backend switch works end-to-end.
when defined(tripwireUnittest2):
  import std/[tables, options]
  import unittest2 as u2
  import tripwire/[types, errors, timeline, sandbox, verify, intercept,
                  integration_unittest]

  type
    U2Plugin = ref object of Plugin
    U2Resp = ref object of MockResponse
      v: int
  method realize(r: U2Resp): int = r.v
  let u2Plugin = U2Plugin(name: "u2", enabled: true)

  proc u2Call(a: int): int =
    tripwireInterceptBody(u2Plugin, "u2Call",
      fingerprintOf("u2Call", @[$a]),
      U2Resp):
      {.noRewrite.}:
        a

  u2.suite "integration_unittest2":
    u2.test "tripwire test: works with unittest2 backend":
      # Real nested test: verifies the lifecycle push/pop/verifyAll path
      # through unittest2 instead of std/unittest. Under unittest2 we
      # still can't assert the defect-bearing negative case via an outer
      # expect (the backend's test-body handler also swallows), so we
      # exercise only the happy path and let E1's direct-invocation
      # tests carry the negative assertions.
      var ran = false
      integration_unittest.test "inner-u2":
        let v = currentVerifier()
        u2.check v != nil
        let m = newMock("u2Call", fingerprintOf("u2Call", @["3"]),
          U2Resp(v: 33),
          (filename: "t.nim", line: 1, column: 0))
        registerMock(v, "u2", m)
        u2.check u2Call(3) == 33
        v.timeline.markAsserted(v.timeline.entries[0])
        ran = true
      u2.check ran

    u2.test "backend alias is unittest2 under -d:tripwireUnittest2":
      u2.check backendName == "unittest2"
else:
  discard
