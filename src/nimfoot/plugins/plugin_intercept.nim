## nimfoot/plugins/plugin_intercept.nim — TRM-safe intercept helper.
##
## Problem: Nim 2.2.6's TRM pattern-matching engine silently skips TRM
## rewriting when the template body calls another template that takes a
## `typedesc` parameter. The failure mode is:
##
##   * TRM is declared (no error)
##   * Pattern matcher reports "declared but not used"
##   * The user-visible call hits the real proc instead of the mock
##
## `nimfoot/intercept.nim`'s `nimfootInterceptBody` combinator takes
## `responseType: typedesc`, which triggers this silent-skip. Rather than
## modify the shared combinator (reserved for the core track), plugins
## call `nimfootPluginIntercept` below — a type-identical combinator whose
## `responseType` parameter is `untyped` so TRM expansion succeeds.
##
## The body is a line-for-line port of `nimfootInterceptBody` (see
## src/nimfoot/intercept.nim). The only delta is `responseType: untyped`.
## When `respType` is used as a type expression at expansion time (e.g.
## `respType(resp).realize()`) Nim substitutes the untyped AST node and
## resolves the type at the caller's scope — identical behavior to the
## typed form.

import std/[tables, options]
import ../[types, errors, timeline, sandbox, verify, cap_counter, intercept]
export options.isSome, options.isNone, options.get

template nimfootPluginIntercept*(plugin: Plugin, procName: string,
                                 fingerprint: string,
                                 respType: untyped,
                                 spyBody: untyped): untyped {.dirty.} =
  ## Plugin-facing intercept combinator. Identical semantics to
  ## `nimfoot/intercept.nimfootInterceptBody`; differs only in the
  ## `respType` parameter being `untyped` to survive TRM expansion.
  bind nimfootCountRewrite, currentVerifier, newLeakedInteractionDefect,
    newPostTestInteractionDefect, getThreadId, instantiationInfo,
    newUnmockedInteractionDefect, popMatchingMock, record, fingerprintOf,
    supportsPassthrough, passthroughFor, realize,
    initOrderedTable, isSome, isNil, get
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
  # Record the call-site fingerprint in args[".fp"] so assertMock can
  # match by (procName, fingerprint) rather than procName alone.
  var nfArgs = initOrderedTable[string, string]()
  nfArgs[".fp"] = fingerprint
  discard nfVerifier.timeline.record(plugin, procName, nfArgs,
    (if nfMockOpt.isSome: nfMockOpt.get.response else: nil),
    (file: nfSite.filename, line: nfSite.line, column: nfSite.column))
  if nfMockOpt.isNone:
    if plugin.supportsPassthrough() and plugin.passthroughFor(procName):
      spyBody
    else:
      raise newUnmockedInteractionDefect(plugin.name, procName, fingerprint,
        (file: nfSite.filename, line: nfSite.line, column: nfSite.column))
  else:
    respType(nfMockOpt.get.response).realize()
