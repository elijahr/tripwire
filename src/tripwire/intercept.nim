## tripwire/intercept.nim — shared TRM body helpers.
##
## Plugin authors call `tripwireInterceptBody` inside every TRM body.
## It encapsulates the required sequence: cap-count, guard, mock lookup,
## timeline record, spy-or-raise.
import std/[tables, options, deques]
import ./[types, errors, timeline, sandbox, verify, cap_counter]

proc nfCollectMockFingerprints*(v: Verifier, pluginName: string): seq[string] =
  ## Collect argFingerprints of mocks currently queued for `pluginName`.
  ## Exposed so TRM combinators (whose `{.dirty.}` expansion must not force
  ## every caller to import `std/deques`) can call it as a real proc.
  result = @[]
  if pluginName in v.mockQueues:
    for m in v.mockQueues[pluginName].mocks:
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

method realize*(r: MockResponse): auto {.base.} =
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
