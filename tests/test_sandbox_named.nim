## tests/test_sandbox_named.nim — Task 5.1: `sandbox(name, body)` overload.
##
## Verifies the named-variant template:
##   * creates a fresh Verifier with `.name == name`,
##   * preserves first-violation-wins semantics,
##   * carries the user-provided label into UnassertedInteractionsDefect
##     messages,
##   * coexists unambiguously with the existing unnamed `sandbox: body`.

import std/[unittest, tables]
import tripwire/[types, errors, timeline, sandbox, verify]

suite "sandbox (named overload)":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "sandbox name: labels the fresh verifier":
    var observedName = ""
    var ran = false
    sandbox "my-test-name":
      observedName = currentVerifier().name
      ran = true
    check ran
    check observedName == "my-test-name"

  test "sandbox name: unasserted-interactions defect carries label":
    ## Trigger UnassertedInteractionsDefect by recording an interaction
    ## without marking it asserted. The raised defect's message must embed
    ## the user-provided sandbox label (via verifier.name).
    var raised = false
    var gotMsg = ""
    try:
      sandbox "labeled-sandbox":
        let v = currentVerifier()
        let p = Plugin(name: "p", enabled: true)
        let resp = MockResponse()
        discard v.timeline.record(p, "someProc",
          initOrderedTable[string, string](), resp,
          (file: "x.nim", line: 1, column: 0))
    except UnassertedInteractionsDefect as e:
      raised = true
      gotMsg = e.msg
    check raised
    check gotMsg == "1 interactions recorded but not asserted " &
      "in verifier 'labeled-sandbox'" & FFIScopeFooter

  test "unnamed sandbox still works alongside named":
    ## Both overloads disambiguate correctly in the same scope.
    var unnamedRan = false
    var namedRan = false
    var namedName = ""
    sandbox:
      unnamedRan = true
      check currentVerifier().name == ""
    sandbox "second":
      namedRan = true
      namedName = currentVerifier().name
    check unnamedRan
    check namedRan
    check namedName == "second"
