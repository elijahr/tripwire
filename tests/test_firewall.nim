## tests/test_firewall.nim — per-sandbox firewall: `allow`, `restrict`,
## matchers, and `firewallMode`.
##
## Covers the bigfoot-style firewall surface registered against the
## current verifier:
##   * `allow(plugin)`                 — blanket plugin-name shorthand.
##   * `allow(plugin, predicate)`      — closure escape hatch.
##   * `allow(plugin, M(...))`         — matcher DSL.
##   * `restrict(...)`                 — inverse ceiling.
##   * `firewallMode = fmWarn`         — warns on stderr, then passes through.
##   * `firewallMode = fmError`        — raises (default).
##   * Predicate keyed on plugin A doesn't affect plugin B's calls.
##   * Multiple predicates compose with OR semantics.
##   * Predicate scope is the sandbox: predicates are released on pop.
##   * MockPlugin's blanket `passthroughFor` still works (no regression).
##
## The wrapper uses `tripwirePluginIntercept` (the plugin-facing
## combinator) because every shipped plugin routes through it; covering
## the typed-form `tripwireInterceptBody` separately is unnecessary —
## both code paths share `sandboxAllowsFor` / `sandboxRestrictsFor`.
## Only ONE wrapper proc is defined here so this test file adds exactly
## ONE TRM rewrite to the aggregate harness's compilation-unit cap
## (cap_counter.nim, TripwireCapThreshold = 15).
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

suite "firewall":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "allow(plugin, predicate) match -> spy body runs":
    sandbox:
      let v = currentVerifier()
      allow(ptPluginA, proc(procName, fp: string): bool =
        fp.contains("127.0.0.1"))
      check fetchA("127.0.0.1") == "real-A:127.0.0.1"
      # The interception was recorded; mark it asserted so verifyAll
      # passes guarantee #2.
      check v.timeline.entries.len == 1
      v.timeline.markAsserted(v.timeline.entries[0])

  test "allow(plugin, predicate) miss -> UnmockedInteractionDefect":
    expect UnmockedInteractionDefect:
      sandbox:
        allow(ptPluginA, proc(procName, fp: string): bool =
          fp.contains("127.0.0.1"))
        # 8.8.8.8 is outside the predicate's pattern; must raise.
        discard fetchA("8.8.8.8")

  test "allow keyed on a different plugin does not leak":
    # Register a permissive predicate against `mockPluginInstance` and
    # verify it does NOT grant passthrough to ptPluginA's calls.
    expect UnmockedInteractionDefect:
      sandbox:
        allow(mockPluginInstance,
          proc(procName, fp: string): bool = true)
        discard fetchA("anyhost")

  test "multiple allow predicates OR together":
    sandbox:
      let v = currentVerifier()
      allow(ptPluginA, proc(procName, fp: string): bool =
        fp.contains("127.0.0.1"))
      allow(ptPluginA, proc(procName, fp: string): bool =
        fp.contains("localhost"))
      # First predicate matches:
      check fetchA("127.0.0.1") == "real-A:127.0.0.1"
      # Second predicate matches:
      check fetchA("localhost") == "real-A:localhost"
      check v.timeline.entries.len == 2
      v.timeline.markAsserted(v.timeline.entries[0])
      v.timeline.markAsserted(v.timeline.entries[1])

  test "allow scope ends with sandbox":
    sandbox:
      allow(ptPluginA, proc(procName, fp: string): bool = true)
      let v = currentVerifier()
      check v.allowPredicates.len == 1
      check fetchA("anything") == "real-A:anything"
      v.timeline.markAsserted(v.timeline.entries[0])

    # Outside the sandbox: a fresh sandbox must NOT see the previous
    # predicate. The new predicate-free sandbox should raise on an
    # unmocked call.
    expect UnmockedInteractionDefect:
      sandbox:
        let v2 = currentVerifier()
        check v2.allowPredicates.len == 0
        discard fetchA("anything")

  test "allow outside sandbox -> LeakedInteractionDefect":
    expect LeakedInteractionDefect:
      allow(ptPluginA, proc(procName, fp: string): bool = true)

  test "MockPlugin blanket passthrough still works (no regression)":
    # MockPlugin's `passthroughFor` returns true for every procName;
    # the sandbox-level firewall is an EXTENSION, not a replacement.
    check mockPluginInstance.supportsPassthrough() == true
    check mockPluginInstance.passthroughFor("anything") == true

  # ---- Plugin-name shorthand --------------------------------------------

  test "allow(plugin) blanket lets any call through":
    sandbox:
      let v = currentVerifier()
      allow(ptPluginA)
      check fetchA("any-1") == "real-A:any-1"
      check fetchA("any-2") == "real-A:any-2"
      check v.timeline.entries.len == 2
      v.timeline.markAsserted(v.timeline.entries[0])
      v.timeline.markAsserted(v.timeline.entries[1])

  # ---- Matcher DSL ------------------------------------------------------

  test "allow(plugin, M(host=...)) matches by host substring":
    sandbox:
      let v = currentVerifier()
      allow(ptPluginA, M(host = "127.0.0.1"))
      check fetchA("127.0.0.1") == "real-A:127.0.0.1"
      v.timeline.markAsserted(v.timeline.entries[0])

  test "allow(plugin, M(host=...)) miss raises":
    expect UnmockedInteractionDefect:
      sandbox:
        allow(ptPluginA, M(host = "127.0.0.1"))
        discard fetchA("evil.example.com")

  test "matcher wildcard host: *.example.com":
    sandbox:
      let v = currentVerifier()
      allow(ptPluginA, M(host = "*.example.com"))
      check fetchA("api.example.com") == "real-A:api.example.com"
      v.timeline.markAsserted(v.timeline.entries[0])

  test "matcher wildcard host: 127.0.0.*":
    sandbox:
      let v = currentVerifier()
      allow(ptPluginA, M(host = "127.0.0.*"))
      check fetchA("127.0.0.7") == "real-A:127.0.0.7"
      v.timeline.markAsserted(v.timeline.entries[0])

  # ---- restrict ---------------------------------------------------------

  test "restrict alone, matched call: still raises (no allow set)":
    # Spec: restrict is a CEILING, not a permission. Even when a call
    # matches a restrict entry, it must ALSO match an allow entry to
    # pass through. With no allow set, every call raises.
    expect UnmockedInteractionDefect:
      sandbox:
        restrict(ptPluginA, proc(procName, fp: string): bool =
          fp.contains("127.0.0.1"))
        discard fetchA("127.0.0.1")

  test "restrict alone, unmatched call: raises (short-circuit)":
    expect UnmockedInteractionDefect:
      sandbox:
        restrict(ptPluginA, proc(procName, fp: string): bool =
          fp.contains("127.0.0.1"))
        # 8.8.8.8 is outside the restrict ceiling; this short-circuits
        # without consulting `allow`.
        discard fetchA("8.8.8.8")

  test "restrict + allow: allow only takes effect within restrict":
    # restrict permits 127.* prefix and localhost; allow within widens
    # to host=localhost. An attempt to allow 8.8.8.8 is impossible
    # because restrict gates the call before allow is consulted.
    sandbox:
      let v = currentVerifier()
      restrict(ptPluginA, proc(procName, fp: string): bool =
        fp.contains("127.") or fp.contains("localhost"))
      allow(ptPluginA, M(host = "localhost"))
      check fetchA("localhost") == "real-A:localhost"
      v.timeline.markAsserted(v.timeline.entries[0])
    expect UnmockedInteractionDefect:
      sandbox:
        restrict(ptPluginA, proc(procName, fp: string): bool =
          fp.contains("127.") or fp.contains("localhost"))
        # Wide-open allow: restrict still wins.
        allow(ptPluginA)
        discard fetchA("8.8.8.8")

  # ---- firewallMode -----------------------------------------------------

  test "firewallMode fmError (default) raises on unmocked":
    expect UnmockedInteractionDefect:
      sandbox:
        check currentVerifier().firewallMode == fmError
        discard fetchA("nope")

  test "firewallMode fmWarn proceeds via passthrough":
    sandbox:
      let v = currentVerifier()
      v.firewallMode = fmWarn
      # No allow / restrict configured. Should NOT raise; instead emits
      # a stderr warning and runs the spy body.
      check fetchA("anywhere") == "real-A:anywhere"
      check v.timeline.entries.len == 1
      v.timeline.markAsserted(v.timeline.entries[0])

  test "guard(v, fmWarn) sugar":
    sandbox:
      let v = currentVerifier()
      guard(v, fmWarn)
      check v.firewallMode == fmWarn
      check fetchA("foo") == "real-A:foo"
      v.timeline.markAsserted(v.timeline.entries[0])
