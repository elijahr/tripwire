## tests/test_sandbox_passthrough.nim — per-sandbox passthrough predicate.
##
## Covers `sandbox.passthrough(plugin, predicate)` registered against the
## current verifier:
##   * Predicate matches → spy body runs, no defect raised.
##   * Predicate doesn't match → `UnmockedInteractionDefect` raised.
##   * Predicate keyed on plugin A doesn't affect plugin B's calls.
##   * Multiple predicates compose with OR semantics.
##   * Predicate scope is the sandbox: predicates are released on pop.
##   * MockPlugin's blanket passthrough still works (no regression).
##
## The wrapper uses `tripwirePluginIntercept` (the plugin-facing
## combinator) because every shipped plugin routes through it; covering
## the typed-form `tripwireInterceptBody` separately is unnecessary —
## both code paths share `sandboxPassthroughFor`. Only ONE wrapper proc
## is defined here so this test file adds exactly ONE TRM rewrite to the
## aggregate harness's compilation-unit cap (cap_counter.nim,
## TripwireCapThreshold = 15).
import std/[unittest, strutils]
import tripwire/[types, errors, timeline, sandbox, verify, intercept]
import tripwire/plugins/[plugin_intercept, mock]

# ---- One test plugin + one wrapper proc (= 1 TRM rewrite) ---------------
type
  PtPluginA* = ref object of Plugin
  PtResp* = ref object of MockResponse
    val*: string

method realize*(r: PtResp): string = r.val

let ptPluginA* = PtPluginA(name: "ptA", enabled: true)

# Real-call body returns a sentinel string so tests can distinguish spy
# mode (sentinel returned) from mocked mode (mock value returned).
proc fetchA(host: string): string =
  tripwirePluginIntercept(ptPluginA, "fetchA",
    fingerprintOf("fetchA", @[host]),
    PtResp):
    {.noRewrite.}:
      "real-A:" & host

suite "sandbox passthrough":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "predicate matches -> spy body runs":
    sandbox:
      let v = currentVerifier()
      passthrough(ptPluginA, proc(procName, fp: string): bool =
        fp.contains("127.0.0.1"))
      check fetchA("127.0.0.1") == "real-A:127.0.0.1"
      # The interception was recorded; mark it asserted so verifyAll
      # passes guarantee #2.
      check v.timeline.entries.len == 1
      v.timeline.markAsserted(v.timeline.entries[0])

  test "predicate does not match -> UnmockedInteractionDefect":
    expect UnmockedInteractionDefect:
      sandbox:
        passthrough(ptPluginA, proc(procName, fp: string): bool =
          fp.contains("127.0.0.1"))
        # 8.8.8.8 is outside the predicate's pattern; must raise.
        discard fetchA("8.8.8.8")

  test "predicate keyed on a different plugin does not leak":
    # Register a permissive predicate against `mockPluginInstance` and
    # verify it does NOT grant passthrough to ptPluginA's calls.
    # Plugin identity is by ref equality (see sandboxPassthroughFor in
    # src/tripwire/sandbox.nim).
    expect UnmockedInteractionDefect:
      sandbox:
        passthrough(mockPluginInstance,
          proc(procName, fp: string): bool = true)
        discard fetchA("anyhost")

  test "multiple predicates OR together":
    sandbox:
      let v = currentVerifier()
      passthrough(ptPluginA, proc(procName, fp: string): bool =
        fp.contains("127.0.0.1"))
      passthrough(ptPluginA, proc(procName, fp: string): bool =
        fp.contains("localhost"))
      # First predicate matches:
      check fetchA("127.0.0.1") == "real-A:127.0.0.1"
      # Second predicate matches:
      check fetchA("localhost") == "real-A:localhost"
      check v.timeline.entries.len == 2
      v.timeline.markAsserted(v.timeline.entries[0])
      v.timeline.markAsserted(v.timeline.entries[1])

  test "predicate scope ends with sandbox":
    sandbox:
      passthrough(ptPluginA, proc(procName, fp: string): bool = true)
      let v = currentVerifier()
      check v.passthroughPredicates.len == 1
      check fetchA("anything") == "real-A:anything"
      v.timeline.markAsserted(v.timeline.entries[0])

    # Outside the sandbox: a fresh sandbox must NOT see the previous
    # predicate. The new predicate-free sandbox should raise on an
    # unmocked call.
    expect UnmockedInteractionDefect:
      sandbox:
        let v2 = currentVerifier()
        check v2.passthroughPredicates.len == 0
        discard fetchA("anything")

  test "passthrough outside sandbox -> LeakedInteractionDefect":
    expect LeakedInteractionDefect:
      passthrough(ptPluginA, proc(procName, fp: string): bool = true)

  test "MockPlugin blanket passthrough still works (no regression)":
    # MockPlugin's `passthroughFor` returns true for every procName;
    # the sandbox-level predicate is an EXTENSION, not a replacement.
    # The blanket-passthrough behavior is asserted directly so any
    # regression in the OR-clause in plugin_intercept.nim:74-75 fails
    # this assertion deterministically.
    check mockPluginInstance.supportsPassthrough() == true
    check mockPluginInstance.passthroughFor("anything") == true
