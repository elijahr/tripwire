## tests/test_hints.nim — unit + integration coverage for
## `nearestMockHints` (v0.1 additive feature on UnmockedInteractionDefect).
##
## Coverage:
##   1. Pure helper — exact match suppressed, distance-1 included,
##      distance-2 excluded, empty candidates, stable order.
##   2. Integration — with a verifier holding one registered mock whose
##      fingerprint is distance-1 from the intercepted call's fingerprint,
##      the raised `UnmockedInteractionDefect.msg` contains a
##      "Did you mean:" block naming the registered fingerprint.
##   3. Negative integration — with a distant registered mock, the
##      defect message does NOT contain "Did you mean:" noise.
##
## These tests deliberately use only the public surface of
## `tripwire/errors` and the existing `tripwire/intercept` combinator.

import std/[unittest, strutils, tables, options]
import tripwire/[types, errors, timeline, sandbox, verify, intercept]

# ---- 1. Pure helper ------------------------------------------------------

suite "nearestMockHints (pure helper)":
  test "exact-match candidate is suppressed (already matched upstream)":
    check nearestMockHints("foo", @["foo"]) == newSeq[string]()

  test "distance-1 candidate is suggested":
    check nearestMockHints("foo", @["fop"]) == @["fop"]

  test "distance-2 candidate is excluded":
    check nearestMockHints("foo", @["xyz"]) == newSeq[string]()

  test "empty candidate list returns empty":
    check nearestMockHints("foo", newSeq[string]()) == newSeq[string]()

  test "mixed candidates preserved in insertion order, distant dropped":
    # fop, fpo, fos are each distance-1; xyz is distance-3 and is dropped.
    check nearestMockHints("foo", @["fop", "fpo", "xyz", "fos"]) ==
          @["fop", "fpo", "fos"]

  test "duplicate near candidates appear once per occurrence":
    # No dedup policy — candidates feed in as-is (callers dedup upstream
    # if they want). Document the behavior so a future change is loud.
    check nearestMockHints("foo", @["fop", "fop"]) == @["fop", "fop"]

  test "realistic URL-fingerprint style, single edit":
    let actual = "getContent|http://example.com/foo"
    let registered = "getContent|http://example.com/bar"
    # 3 edits (foo -> bar): should NOT be a hint at distance 1.
    check nearestMockHints(actual, @[registered]) == newSeq[string]()

  test "realistic URL-fingerprint style, trailing slash typo":
    let actual = "getContent|http://example.com/foo"
    let registered = "getContent|http://example.com/fo"
    # 1 edit (deletion of final 'o'): IS a hint at distance 1.
    check nearestMockHints(actual, @[registered]) == @[registered]

# ---- 2. Integration: near-match mock yields "Did you mean:" --------------
# Reuses the TestIntPlugin from test_intercept.nim's style but we can't
# import that module without dragging its suites in. Redeclare minimally.

type
  HintPlugin = ref object of Plugin
  HintResp = ref object of MockResponse
    val: int

method realize(r: HintResp): int = r.val

let hintPlugin = HintPlugin(name: "hint", enabled: true)

proc hintProc(tag: string): int =
  tripwireInterceptBody(hintPlugin, "hintProc",
    fingerprintOf("hintProc", @[tag]),
    HintResp):
    {.noRewrite.}:
      0

suite "nearestMockHints (integration via UnmockedInteractionDefect)":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "near-miss registered mock appears in 'Did you mean:' block":
    let v = newVerifier("t")
    discard pushVerifier(v)
    try:
      # Register a mock at fingerprint hintProc|bar. The actual call uses
      # "baz" (distance 1 from "bar"), producing fingerprint hintProc|baz.
      let registeredFp = fingerprintOf("hintProc", @["bar"])
      let m = newMock("hintProc", registeredFp, HintResp(val: 0),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(v, "hint", m)
      var raised = false
      try:
        discard hintProc("baz")
      except UnmockedInteractionDefect as e:
        raised = true
        check "Did you mean" in e.msg
        check registeredFp in e.msg
        check e.nearestMockHints == @[registeredFp]
      check raised
    finally:
      discard popVerifier()

  test "distant registered mock produces NO hint block":
    let v = newVerifier("t")
    discard pushVerifier(v)
    try:
      let registeredFp = fingerprintOf("hintProc", @["zzzzz"])
      let m = newMock("hintProc", registeredFp, HintResp(val: 0),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(v, "hint", m)
      var raised = false
      try:
        discard hintProc("a")
      except UnmockedInteractionDefect as e:
        raised = true
        check "Did you mean" notin e.msg
        check e.nearestMockHints == newSeq[string]()
      check raised
    finally:
      discard popVerifier()

  test "no registered mocks => no hint block, field empty":
    let v = newVerifier("t")
    discard pushVerifier(v)
    try:
      var raised = false
      try:
        discard hintProc("anything")
      except UnmockedInteractionDefect as e:
        raised = true
        check "Did you mean" notin e.msg
        check e.nearestMockHints == newSeq[string]()
      check raised
    finally:
      discard popVerifier()
