## tests/test_mock_expect.nim — F2: MockPlugin expect DSL macro.
##
## **Nim TRM gotcha** (discovered during F2 implementation): when a TRM-
## patterned call appears DIRECTLY inside a `unittest.test:` block (as
## opposed to inside a regular proc called from the test block), the TRM
## fires only in the FIRST `test:` block of a compilation unit. Subsequent
## `test:` blocks silently skip the rewrite. The root cause is in Nim's
## TRM/dirty-template compile-order interaction (see isolated repro in the
## commit body).
##
## Workaround: always call mockable procs via a thin wrapper proc from
## inside the test body. In real-world usage this is the natural pattern
## — you mock a low-level proc (`fetch`) and your test exercises a
## higher-level proc (`loadUser`) that calls it — so the gotcha rarely
## surfaces in practice. Tests that want to exercise the mocked proc
## directly declare a local helper proc.
import std/[unittest, options, tables, deques]
import tripwire/[types, errors, timeline, sandbox, verify, intercept,
                macros as nfmacros]
import tripwire/plugins/mock

# User-declared proc that we want to mock.
proc computeThing(x, y: int): int =
  x + y   # real impl; TRM should intercept this

# Module-scope TRM emission. The dummy args (0, 0) only provide arity and
# types for the TRM's formal params; the values are not used at runtime.
mockable(computeThing(0, 0))

# Wrapper proc — calling the mocked proc from here (not directly from the
# `test:` block) sidesteps the unittest-dirty-template TRM gotcha.
proc callComputeThing(x, y: int): int = computeThing(x, y)

suite "MockPlugin expect DSL":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "expect registers a mock and the TRM intercepts":
    sandbox:
      let v = currentVerifier()
      mock.expect computeThing(2, 3):
        respond value: 42
      let got = callComputeThing(2, 3)
      doAssert got == 42, "mock did not intercept: got " & $got
      v.timeline.markAsserted(v.timeline.entries[0])

  test "second sandbox block also fires TRM":
    sandbox:
      let v = currentVerifier()
      mock.expect computeThing(1, 1):
        respond value: 99
      let mocked = callComputeThing(1, 1)
      doAssert mocked == 99, "second-block mock did not fire: got " & $mocked
      v.timeline.markAsserted(v.timeline.entries[0])

  test "unmocked args route through passthrough":
    # MockPlugin's passthrough is on: a call whose fingerprint does not
    # match any registered mock runs the real impl AND records an
    # interaction for Guarantee 2.
    sandbox:
      let v = currentVerifier()
      # No `expect` — no mocks registered. The module-TRM still fires,
      # records an interaction, and falls through to the real proc.
      let got = callComputeThing(10, 20)
      doAssert got == 30, "passthrough did not run real impl: got " & $got
      doAssert v.timeline.entries.len == 1,
        "expected 1 passthrough interaction, got " & $v.timeline.entries.len
      v.timeline.markAsserted(v.timeline.entries[0])
