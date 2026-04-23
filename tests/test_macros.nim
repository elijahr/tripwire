## tests/test_macros.nim — D1 unit tests for DSL primitives + AST helpers.
##
## `inAnyOrder` lives in tests/test_context.nim (Task A3.5); not duplicated here.
import std/[unittest, macros]
import nimfoot/[types, errors, timeline, sandbox, verify, intercept,
                macros as nfmacros]

suite "macros":
  test "respond template re-emits its body":
    var fired = false
    respond:
      fired = true
    check fired

  test "responded template re-emits its body":
    var fired = false
    responded:
      fired = true
    check fired

  test "request template re-emits its body":
    var fired = false
    request:
      fired = true
    check fired

  test "hasEmittedTRM / markTRMEmitted roundtrip at compile time":
    # Exercised at compile time; the proc symbols are {.compileTime.} so we
    # wrap the assertions in a `static:` block.
    static:
      doAssert not hasEmittedTRM("procA_D1_unique")
      markTRMEmitted("procA_D1_unique")
      doAssert hasEmittedTRM("procA_D1_unique")
      # Idempotent: second mark is a no-op.
      markTRMEmitted("procA_D1_unique")
      doAssert hasEmittedTRM("procA_D1_unique")
    check true   # static: block would have failed compilation otherwise.
