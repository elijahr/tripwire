## tests/test_mock_assert.nim — F3: MockPlugin assert DSL macro.
import std/[unittest, options, tables, deques]
import tripwire/[types, errors, timeline, sandbox, verify, intercept,
                macros as nfmacros]
import tripwire/plugins/mock

proc computeThing(x, y: int): int = x + y
mockable(computeThing(0, 0))

# Wrapper proc — see test_mock_expect.nim for the TRM/unittest gotcha.
proc callComputeThing(x, y: int): int = computeThing(x, y)

suite "MockPlugin assert DSL":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "expect then assert completes the guarantee cycle":
    sandbox:
      mock.expect computeThing(2, 3):
        respond value: 42
      discard callComputeThing(2, 3)
      mock.assertMock computeThing(2, 3):
        responded value: 42
      # sandbox's verifyAll passes now: mock consumed, interaction asserted.

  test "assert without matching interaction fails":
    sandbox:
      let v = currentVerifier()
      mock.expect computeThing(1, 1):
        respond value: 2
      discard callComputeThing(1, 1)
      var raised = false
      try:
        mock.assertMock computeThing(7, 7):   # wrong args
          responded value: 2
      except AssertionDefect:
        raised = true
      doAssert raised, "assertMock should raise AssertionDefect on no match"
      # Mark the real interaction asserted to avoid Guarantee 2 failing.
      v.timeline.markAsserted(v.timeline.entries[0])
