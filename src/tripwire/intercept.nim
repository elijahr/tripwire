## tripwire/intercept.nim — shared TRM body helpers.
##
## Plugin authors call `tripwireInterceptBody` inside every TRM body.
## It encapsulates the required sequence: cap-count, guard, mock lookup,
## timeline record, spy-or-raise.
import std/[tables, options, deques]
import ./[types, errors, timeline, sandbox, verify, cap_counter]

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
    realize, nfCollectMockFingerprints, firewallShouldRaise
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
    if nfVerifier.isNil:
      raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
    if not nfVerifier.active:
      raise newPostTestInteractionDefect(nfVerifier.name,
        nfVerifier.generation, plugin.name, procName)
    let nfMockOpt = nfVerifier.popMatchingMock(plugin.name, procName,
                                                fingerprint)
    let nfSite = instantiationInfo()
    discard nfVerifier.timeline.record(plugin, procName,
      initOrderedTable[string, string](),
      (if nfMockOpt.isSome: nfMockOpt.get.response else: nil),
      (file: nfSite.filename, line: nfSite.line, column: nfSite.column))
    if nfMockOpt.isNone:
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
