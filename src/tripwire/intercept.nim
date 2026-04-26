## tripwire/intercept.nim — shared TRM body helpers.
##
## Plugin authors call `tripwireInterceptBody` inside every TRM body.
## It encapsulates the required sequence: cap-count, guard, mock lookup,
## timeline record, spy-or-raise.
import std/[tables, options, deques]
import ./[types, errors, timeline, sandbox, verify, cap_counter, config,
          plugin_base]

proc nfCollectMockFingerprints*(v: Verifier, pluginName: string):
    seq[string] {.raises: [].} =
  ## Collect argFingerprints of mocks currently queued for `pluginName`.
  ## Exposed so TRM combinators (whose `{.dirty.}` expansion must not force
  ## every caller to import `std/deques`) can call it as a real proc.
  ##
  ## Annotated `{.raises: [].}` because TRM bodies expand inside consumer
  ## procs that may declare strict raises clauses (e.g., chronos
  ## `async: (raises: [HttpError])`). `withValue` is used in lieu of
  ## `mockQueues[pluginName]` to keep the table access non-raising.
  result = @[]
  v.mockQueues.withValue(pluginName, qPtr):
    for m in qPtr[].mocks:
      result.add(m.argFingerprint)

# ---- Defense 3: real cap counter (replaces A7 stub) ---------------------
export cap_counter.tripwireCountRewrite, cap_counter.TripwireCapThreshold

# ---- Outside-sandbox firewall predicate ---------------------------------
#
# A4'''.4 guard mode: when [tripwire.firewall].guard='warn' is configured,
# unmocked TRM calls outside any sandbox can pass through to the real impl
# (when the plugin supports it) instead of raising LeakedInteractionDefect.
#
# CONSUMPTION SHAPE: this predicate is callable from a TRM body, but only
# under `-d:tripwireFirewallGuardMode`. See the `tripwireInterceptBody`
# combinator below for the guarded call site and the SHAPE NOTES on why
# the matrix-default codepath stays single-raise.
proc outsideSandboxShouldPassthrough*(plugin: Plugin, procName: string,
    callsite: tuple[filename: string, line: int]): bool {.raises: [].} =
  ## Outside-sandbox firewall decision, bool form. Returns `true` iff
  ## guard=fmWarn AND the plugin can passthrough (also emits the stderr
  ## warning as a side effect). RAISES on the raise paths:
  ##   - guard=fmError → raises LeakedInteractionDefect.
  ##   - guard=fmWarn AND plugin can't passthrough → raises
  ##     OutsideSandboxNoPassthroughDefect.
  ##
  ## `{.raises: [].}` is load-bearing: both raised types are Defects (not
  ## CatchableErrors), so the empty raises clause is correct (Defects
  ## bypass Nim's effect-system raises tracking). Listing concrete defect
  ## types in the raises clause empirically trips vmgen 1821,23 in Cell 3.
  ##
  ## getConfig() can raise on first-call config-file parse errors (IOError,
  ## ValueError, parsetoml errors); we suppress those and fall through to
  ## fmError — a config-load failure must NOT mask the underlying
  ## outside-sandbox violation. Operator should see the
  ## LeakedInteractionDefect first; fix the sandbox issue and then fix
  ## any config-file syntax issue separately.
  var guardMode = fmError
  try:
    guardMode = getConfig().firewall.guard
  except Exception:
    guardMode = fmError
  case guardMode
  of fmError:
    raise newLeakedInteractionDefect(getThreadId(),
      (filename: callsite.filename, line: callsite.line, column: 0))
  of fmWarn:
    if plugin.supportsPassthrough() and plugin.passthroughFor(procName):
      try:
        stderr.writeLine("tripwire(guard=warn): unmocked " &
          plugin.name & "." & procName & " at " &
          callsite.filename & ":" & $callsite.line)
      except IOError:
        discard  # matches sandbox.emitFirewallWarning precedent
      return true
    else:
      raise newOutsideSandboxNoPassthroughDefect(plugin.name, procName,
        (filename: callsite.filename, line: callsite.line))

# ---- Defense 6 primitive -------------------------------------------------
template tripwireGuard*(plugin: Plugin, procName: string): untyped {.dirty.} =
  bind currentVerifier, newLeakedInteractionDefect,
    newPostTestInteractionDefect, getThreadId, instantiationInfo
  let nfVerifier {.inject.} = currentVerifier()
  if nfVerifier.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  if not nfVerifier.active:
    raise newPostTestInteractionDefect(nfVerifier.name,
      nfVerifier.generation, plugin.name, procName)

# ---- realize: plugins MUST override --------------------------------------
# (`supportsPassthrough` / `passthroughFor` base methods now live in
#  `tripwire/plugin_base` so the firewall decision proc in
#  `tripwire/sandbox` can call them without inverting the import graph.)

method realize*(r: MockResponse): auto {.base, gcsafe, raises: [Defect].} =
  ## `raises: [Defect]` is load-bearing — TRM bodies expand inside
  ## consumer procs that may declare strict raises clauses (e.g.,
  ## chronos `async: (raises: [HttpError])`). Defects are not in raises
  ## clauses, so they pass through any strict-raises proc cleanly; a
  ## CatchableError leak here would break composition. Plugin overrides
  ## MUST be raises-compatible (typically `{.raises: [Defect].}` or a
  ## chronos-async equivalent).
  raise newException(Defect,
    "MockResponse.realize must be overridden by each plugin's subclass")

# ---- The combinator ------------------------------------------------------
template tripwireInterceptBody*(plugin: Plugin, procName: string,
                               fingerprint: string,
                               responseType: typedesc,
                               spyBody: untyped): untyped {.dirty.} =
  ## Canonical TRM body combinator. See design §5.3.
  ##
  ## Firewall consultation order for an unmocked call:
  ##   1. plugin's own `passthroughFor(procName)`        (legacy/blanket)
  ##   2. `restrict` gate                                (inverse ceiling)
  ##   3. `allow` gate                                   (per-sandbox firewall)
  ##   4. `firewallMode` decides defect-or-warn
  bind tripwireCountRewrite, currentVerifier, newLeakedInteractionDefect,
    newPostTestInteractionDefect, getThreadId, instantiationInfo,
    newUnmockedInteractionDefect, popMatchingMock, record, fingerprintOf,
    realize, nfCollectMockFingerprints, firewallShouldRaise,
    tagFirewallPassthrough, outsideSandboxShouldPassthrough
  # `{.cast(gcsafe).}` is load-bearing: TRM expansions inline into
  # consumer call sites which under chronos `async: (raises: [...])`
  # are forced to gcsafe. The body legitimately reads top-level `let`
  # plugin instances and a threadvar verifier stack — both
  # gcsafe-equivalent in practice but not provably so to Nim's effect
  # system. See plugin_intercept.tripwirePluginIntercept for the
  # matching cast in the plugin-facing combinator.
  {.cast(gcsafe).}:
    tripwireCountRewrite()
    let nfVerifier {.inject.} = currentVerifier()
    # SHAPE NOTES (Nim 2.2.8 toolchain quirks). See:
    #   docs/upstream-bugs/nim-2.2.8-trm-bind-enum-tags-sigsegv.md
    #   docs/upstream-bugs/nim-2.2.8-vmgen-1821-multi-statement-if-body.md
    #
    # 1. The {.dirty.} template's `bind` list MUST NOT bind enum tag
    #    identifiers. The natural design shape (an
    #    `OutsideSandboxDisposition` enum returned from a free proc and
    #    switched on via `case`) was bisected and rejected: binding the
    #    enum tag identifiers into this combinator's `bind` clause
    #    destabilizes Nim 2.2.8's TRM rewriter on heavy aggregate
    #    compilation (SIGSEGV in Cell 1).  The bool-form predicate
    #    `outsideSandboxShouldPassthrough` avoids that destabilizer.
    #
    # 2. The `if nfVerifier.isNil:` body MUST be a SINGLE statement
    #    under Nim 2.2.8's refc + unittest2 vmgen pipeline (Cell 3).
    #    Adding any second statement to that branch trips
    #    `internal error: vmgen.nim(1821, 23)` inside unittest2's
    #    `failingOnExceptions` wrapper.  Workaround used here: hoist
    #    the guard='warn' passthrough decision into a separate `let`
    #    that is evaluated BEFORE the single-raise if-isNil branch,
    #    using a short-circuit `and` against `nfVerifier.isNil` so the
    #    predicate is never invoked when a verifier is in scope.  The
    #    second `if nfOutsideHandled:` branch is structurally distinct
    #    from `if nfVerifier.isNil:` and so escapes the constraint.
    let nfOutsideHandled = nfVerifier.isNil and
        outsideSandboxShouldPassthrough(plugin, procName,
          (filename: instantiationInfo().filename,
           line: instantiationInfo().line))
    if nfVerifier.isNil and not nfOutsideHandled:
      raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
    if not nfOutsideHandled:
      if not nfVerifier.active:
        raise newPostTestInteractionDefect(nfVerifier.name,
          nfVerifier.generation, plugin.name, procName)
      let nfMockOpt = nfVerifier.popMatchingMock(plugin.name, procName,
                                                  fingerprint)
      let nfSite = instantiationInfo()
      # `record`'s arg list stays unchanged (Nim 2.2.8 refc + unittest2
      # `failingOnExceptions` vmgen 1821,23 crash). Kind discrimination
      # is done via a post-record `tagFirewallPassthrough` call inside
      # the existing `if nfMockOpt.isNone:` branch — that branch
      # already exists for the firewall raise/spy decision, so we're
      # not adding a new control-flow node, only one extra statement
      # inside an existing one.
      let nfRec = nfVerifier.timeline.record(plugin, procName,
        initOrderedTable[string, string](),
        (if nfMockOpt.isSome: nfMockOpt.get.response else: nil),
        (file: nfSite.filename, line: nfSite.line, column: nfSite.column))
      if nfMockOpt.isNone:
        tagFirewallPassthrough(nfRec)
        # Firewall decision is consolidated into `firewallDecide` (a real
        # proc, not a template). The TRM body needs to stay structurally
        # SIMPLE — Nim 2.2.8's term-rewriting macro engine SIGSEGVs when
        # the body of a TRM contains multiple if-statements that themselves
        # contain {.noRewrite.}: blocks (verified by bisecting on
        # tests/test_self_three_guarantees.nim during the firewall-rename
        # refactor). The fix: flatten to a single decision branch, with the
        # raise lifted into a small helper proc and the warn-side preceding
        # spyBody as a plain statement.
        if firewallShouldRaise(nfVerifier, plugin, procName, fingerprint):
          raise newUnmockedInteractionDefect(plugin.name, procName, fingerprint,
            (file: nfSite.filename, line: nfSite.line, column: nfSite.column),
            nil, nfCollectMockFingerprints(nfVerifier, plugin.name))
        spyBody
      else:
        responseType(nfMockOpt.get.response).realize()
    else:
      # guard='warn' passthrough: skip verifier-path entirely, evaluate
      # spyBody as the combinator's trailing expression.  Crucially this
      # is NOT `result = spyBody; return` — TRM expansions also fire at
      # expression-context call sites (e.g. `discard c.request(...)`)
      # where `result` is undeclared.  Returning spyBody as the trailing
      # expression keeps the combinator a value-form expression at every
      # call site, regardless of consumer return-type plumbing.
      spyBody
