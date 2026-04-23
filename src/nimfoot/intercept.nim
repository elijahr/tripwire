## nimfoot/intercept.nim — shared TRM body helpers.
##
## Plugin authors call `nimfootInterceptBody` inside every TRM body.
## It encapsulates the required sequence: cap-count, guard, mock lookup,
## timeline record, spy-or-raise.
import std/[tables, options]
import ./[types, errors, timeline, sandbox, verify]

# ---- Defense 3 stub (full impl in Task D3) ------------------------------
template nimfootCountRewrite*(): untyped =
  ## Stub: no-op in A7. Replaced with compile-time counter in D3.
  discard

# ---- Defense 6 primitive -------------------------------------------------
template nimfootGuard*(plugin: Plugin, procName: string): untyped {.dirty.} =
  bind currentVerifier, newLeakedInteractionDefect,
    newPostTestInteractionDefect, getThreadId, instantiationInfo
  let nfVerifier {.inject.} = currentVerifier()
  if nfVerifier.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  if not nfVerifier.active:
    raise newPostTestInteractionDefect(nfVerifier.name,
      nfVerifier.generation, plugin.name, procName)

# ---- Plugin passthrough base methods -------------------------------------
method supportsPassthrough*(p: Plugin): bool {.base.} = false
method passthroughFor*(p: Plugin, procName: string): bool {.base.} = false

# ---- realize: plugins MUST override --------------------------------------
method realize*(r: MockResponse): auto {.base.} =
  raise newException(Defect,
    "MockResponse.realize must be overridden by each plugin's subclass")

# ---- The combinator ------------------------------------------------------
template nimfootInterceptBody*(plugin: Plugin, procName: string,
                               fingerprint: string,
                               responseType: typedesc,
                               spyBody: untyped): untyped {.dirty.} =
  ## Canonical TRM body combinator. See design §5.3.
  bind nimfootCountRewrite, currentVerifier, newLeakedInteractionDefect,
    newPostTestInteractionDefect, getThreadId, instantiationInfo,
    newUnmockedInteractionDefect, popMatchingMock, record, fingerprintOf,
    supportsPassthrough, passthroughFor, realize
  nimfootCountRewrite()
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
    if plugin.supportsPassthrough() and plugin.passthroughFor(procName):
      spyBody
    else:
      raise newUnmockedInteractionDefect(plugin.name, procName, fingerprint,
        (file: nfSite.filename, line: nfSite.line, column: nfSite.column))
  else:
    responseType(nfMockOpt.get.response).realize()
