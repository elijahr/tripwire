## tests/test_firewall.nim — per-sandbox firewall: `allow`, `restrict`,
## matchers, and `firewallMode`.
##
## Covers the bigfoot-style firewall surface registered against the
## current verifier:
##   * `allow(plugin)`                 — blanket plugin-name shorthand.
##   * `allow(plugin, predicate)`      — closure escape hatch.
##   * `allow(plugin, M(...))`         — matcher DSL.
##   * `restrict(...)`                 — ceiling on `allow` (intersection).
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
#
# Fingerprint shape: `procName=fetchA host=<host>` — the typed-token
# format the matcher DSL anchors on (see `sandbox.matchesFingerprint`).
# Non-HTTP plugins that want to interoperate with `M(host=...)` style
# matchers MUST emit `host=<value>` tokens; the previous bare-host
# `fingerprintOf("fetchA", @[host])` shape relied on the legacy
# token-anywhere matcher and would no longer match under the typed
# format.
proc fetchA(host: string): string =
  tripwirePluginIntercept(ptPluginA, "fetchA",
    "procName=fetchA host=" & host,
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

  test "allow(plugin, M(host=...)) matches by typed host token":
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

  # ---- restrict (ceiling on allow) --------------------------------------

  test "restrict alone authorizes nothing (empty allow ∩ restrict = empty)":
    # `restrict` is a CEILING on `allow`, not a permission grant. With
    # no `allow` registered, the effective permission set is empty
    # regardless of whether the call matches `restrict` — the ceiling
    # filters the permission set, it does not grant.
    expect UnmockedInteractionDefect:
      sandbox:
        restrict(ptPluginA, proc(procName, fp: string): bool =
          fp.contains("127.0.0.1"))
        discard fetchA("127.0.0.1")

  test "restrict alone, unmatched call: raises (no allow, no ceiling-admit)":
    expect UnmockedInteractionDefect:
      sandbox:
        restrict(ptPluginA, proc(procName, fp: string): bool =
          fp.contains("127.0.0.1"))
        # Outside the ceiling AND no allow — both reasons reject.
        discard fetchA("8.8.8.8")

  test "blanket allow + restrict matcher: ceiling narrows broad permission":
    # The canonical bigfoot pattern. `allow(plugin)` permits every
    # call the plugin intercepts; `restrict(plugin, M(...))` is the
    # ceiling that shrinks the permission set down to calls matching
    # the matcher. Calls inside the ceiling pass; calls outside reject.
    sandbox:
      let v = currentVerifier()
      allow(ptPluginA)                                  # broad permit
      restrict(ptPluginA, M(host = "127.0.0.*"))        # ceiling
      check fetchA("127.0.0.1") == "real-A:127.0.0.1"
      check fetchA("127.0.0.42") == "real-A:127.0.0.42"
      check v.timeline.entries.len == 2
      v.timeline.markAsserted(v.timeline.entries[0])
      v.timeline.markAsserted(v.timeline.entries[1])
    expect UnmockedInteractionDefect:
      sandbox:
        allow(ptPluginA)
        restrict(ptPluginA, M(host = "127.0.0.*"))
        # Outside the ceiling; the blanket allow doesn't widen it.
        discard fetchA("8.8.8.8")

  test "restrict + non-matching allow: rejects (intersection is empty)":
    # `allow` matches localhost; `restrict` only admits 127.* / localhost.
    # 8.8.8.8 is outside both, so the intersection rejects it. Conversely
    # localhost is in BOTH and passes — demonstrates "allow ∩ restrict."
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
        # allow widens to "anything" but restrict ceiling still filters.
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

  test "firewall passthrough auto-drains: G2 ignores ikFirewallPassthrough":
    # Regression guard for the paperplanes-driven ergonomics: a call
    # that the firewall AUTHORIZED via `allow` records as
    # `ikFirewallPassthrough` and is NOT subject to Guarantee 2. The
    # user already authorized via `allow(...)` — the assertion is
    # implicit. No `markAsserted` boilerplate; sandbox teardown
    # MUST NOT raise UnassertedInteractionsDefect.
    #
    # Pre-fix, every passthrough test had to manually mark every
    # timeline entry asserted to silence G2; with auto-drain, that
    # boilerplate disappears.
    sandbox:
      let v = currentVerifier()
      allow(ptPluginA, proc(procName, fp: string): bool =
        fp.contains("127.0.0.1"))
      check fetchA("127.0.0.1") == "real-A:127.0.0.1"
      check v.timeline.entries.len == 1
      check v.timeline.entries[0].kind == ikFirewallPassthrough
      check v.timeline.entries[0].asserted == false
      # Deliberately NOT calling markAsserted. Sandbox teardown's
      # verifyAll must still pass — the new G2 contract excludes
      # firewall passthroughs.

  test "mock-matched recordings remain G2-relevant (no auto-drain regression)":
    # Counterpart to the auto-drain test above: a call that was
    # MOCKED (not firewall-passthrough) is still subject to G2.
    # `responded` / `markAsserted` is required.
    expect UnassertedInteractionsDefect:
      sandbox:
        let v = currentVerifier()
        # Register a mock so the call goes the mocked path, not the
        # firewall path.
        v.registerMock("ptA",
          newMock("fetchA", "procName=fetchA host=zzz",
                  PtResp(val: "mocked-A"), instantiationInfo()))
        check fetchA("zzz") == "mocked-A"
        check v.timeline.entries.len == 1
        check v.timeline.entries[0].kind == ikMockMatched
        # Deliberately NOT calling markAsserted. Sandbox teardown
        # MUST raise UnassertedInteractionsDefect.

  # ---- Matcher-precision regression guards ------------------------------
  #
  # These tests pin down the false-positive classes the typed-token
  # fingerprint format eliminates. Pre-fix, the matcher's "any
  # whitespace-token equals field" rule caused spurious matches when
  # the field value appeared anywhere in the fingerprint (e.g., a
  # query-string value, or a method name appearing inside the host).

  test "M(host) does not collide with prefix-extended host":
    # `host=evil-example.com` MUST NOT match `M(host="example.com")`:
    # the value-after-`host=` is `evil-example.com`, not equal.
    expect UnmockedInteractionDefect:
      sandbox:
        allow(ptPluginA, M(host = "example.com"))
        discard fetchA("evil-example.com")

  test "M(port=80) does not collide with port 8080":
    # The fingerprint contains `port=8080`; the value after `port=` is
    # `8080`, not `80`. Pre-fix this leaked because `:8080` contained
    # the substring `:80` under the colon-tokenized splitter.
    # Direct `matchesFingerprint` check (avoids needing a separate
    # plugin proc with a port-bearing fingerprint shape).
    let m = M(port = 80)
    check m.matchesFingerprint(
      "fetchA",
      "procName=fetchA method=GET host=foo.com port=8080") == false

  test "M(host=GET) does not match request whose method is GET":
    # Pre-fix `M(host="GET")` matched any GET request because `GET`
    # appeared as a whitespace token. With anchoring the value after
    # `host=` is `foo.com`, never `GET`.
    let m = M(host = "GET")
    check m.matchesFingerprint(
      "fetchA",
      "procName=fetchA method=GET host=foo.com") == false

  test "M(host=[::1]) matches IPv6 loopback fingerprint":
    # IPv6 hosts go in the `host=` token wrapped in square brackets so
    # the host token stays a single whitespace-delimited unit. Pre-fix
    # the colon-splitter shredded `[::1]` into `[`, ``, ``, `1]` and
    # the matcher couldn't match either bracketed or bare forms.
    let m = M(host = "[::1]")
    check m.matchesFingerprint(
      "fetchA",
      "procName=fetchA method=GET host=[::1] port=80 path=/") == true

  test "non-HTTP fingerprint shape rejects host matcher":
    # Backward-compat doc: a fingerprintOf-shaped fingerprint
    # (`procName|arg0|...`) has no `host=` token, so M(host=...) MUST
    # return false rather than coincidentally matching some substring.
    # Predicate-based allow remains the escape hatch.
    let m = M(host = "anything")
    check m.matchesFingerprint("fetchA", "fetchA|anything|x") == false

  test "non-HTTP fingerprint shape: matcher with no fields trivially matches":
    # Only procName set: an empty Matcher with just procName MUST
    # match regardless of fingerprint shape, since no token-anchored
    # fields are required to be present.
    let m = M(procName = "fetchA")
    check m.matchesFingerprint("fetchA", "fetchA|anything|x") == true
