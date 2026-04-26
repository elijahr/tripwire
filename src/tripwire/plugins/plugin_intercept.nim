## tripwire/plugins/plugin_intercept.nim — TRM-safe intercept helper.
##
## Problem: Nim 2.2.6's TRM pattern-matching engine silently skips TRM
## rewriting when the template body calls another template that takes a
## `typedesc` parameter. The failure mode is:
##
##   * TRM is declared (no error)
##   * Pattern matcher reports "declared but not used"
##   * The user-visible call hits the real proc instead of the mock
##
## `tripwire/intercept.nim`'s `tripwireInterceptBody` combinator takes
## `responseType: typedesc`, which triggers this silent-skip. Rather than
## modify the shared combinator (reserved for the core track), plugins
## call `tripwirePluginIntercept` below — a type-identical combinator whose
## `responseType` parameter is `untyped` so TRM expansion succeeds.
##
## The body is a line-for-line port of `tripwireInterceptBody` (see
## src/tripwire/intercept.nim). The only delta is `responseType: untyped`.
## When `respType` is used as a type expression at expansion time (e.g.
## `respType(resp).realize()`) Nim substitutes the untyped AST node and
## resolves the type at the caller's scope — identical behavior to the
## typed form.

import std/[tables, options]
import ../[types, errors, timeline, sandbox, verify, cap_counter, intercept]
export options.isSome, options.isNone, options.get

proc nfRecordFingerprint*(t: var OrderedTable[string, string],
                          fp: string) {.raises: [].} =
  ## Helper to stuff the call-site fingerprint into an Interaction.args
  ## table without tripping the httpclient/HttpHeaders `[]=` overload
  ## shadowing at TRM expansion sites.
  t[".fp"] = fp

template tripwirePluginIntercept*(plugin: Plugin, procName: string,
                                 fingerprint: string,
                                 respType: untyped,
                                 spyBody: untyped): untyped {.dirty.} =
  ## Plugin-facing intercept combinator. Identical semantics to
  ## `tripwire/intercept.tripwireInterceptBody`; differs only in the
  ## `respType` parameter being `untyped` to survive TRM expansion.
  ##
  ## Firewall consultation order for an unmocked call:
  ##   1. plugin's own `passthroughFor(procName)`        (legacy/blanket)
  ##   2. `restrict` gate                                (inverse ceiling)
  ##   3. `allow` gate                                   (per-sandbox firewall)
  ##   4. `firewallMode` decides defect-or-warn
  bind tripwireCountRewrite, currentVerifier, newLeakedInteractionDefect,
    newPostTestInteractionDefect, getThreadId, instantiationInfo,
    newUnmockedInteractionDefect, popMatchingMock, record, fingerprintOf,
    realize,
    initOrderedTable, isSome, isNil, get, nfRecordFingerprint,
    nfCollectMockFingerprints, firewallShouldRaise
  # block: wrapper gives each expansion its own scope so a plugin module
  # holding two TRMs (e.g. osproc's execProcessSeqTRM + execCmdExTRM) does
  # not emit duplicate `let nfVerifier` bindings in the same module scope.
  # Without this, {.dirty.} template expansion produces
  # "redefinition of 'nfVerifier'" during the second TRM's instantiation.
  #
  # `{.cast(gcsafe).}` is load-bearing: the TRM body inlines into
  # consumer call sites, which under chronos `async: (raises: [...])`
  # are forced to gcsafe. The TRM body legitimately reads top-level
  # `let` plugin instances (e.g. `chronosHttpPluginInstance`) and a
  # threadvar verifier stack — both gcsafe-equivalent in practice but
  # not provably so to Nim's effect system. The cast asserts gcsafe
  # over the entire expansion, including spyBody (which the plugin
  # author owns and is responsible for keeping gcsafe-clean).
  {.cast(gcsafe).}:
    block:
      tripwireCountRewrite()
      let nfVerifier = currentVerifier()
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
      # Routed through nfRecordFingerprint (a real proc) so the TRM expansion
      # site does NOT try to overload-resolve tables.[]= against any nearby
      # HttpHeaders.[]= etc.
      var nfArgs = initOrderedTable[string, string]()
      nfRecordFingerprint(nfArgs, fingerprint)
      discard nfVerifier.timeline.record(plugin, procName, nfArgs,
        (if nfMockOpt.isSome: nfMockOpt.get.response else: nil),
        (file: nfSite.filename, line: nfSite.line, column: nfSite.column))
      if nfMockOpt.isNone:
        # See the matching commentary in tripwire/intercept.nim: TRM body
        # MUST stay structurally simple (single conditional branch) to
        # avoid a Nim-2.2.8 rewriter SIGSEGV. `firewallDecide` does the
        # warn-side stderr emission as a side effect so the body here is
        # just `if fdRaise: raise; spyBody`.
        if firewallShouldRaise(nfVerifier, plugin, procName, fingerprint):
          raise newUnmockedInteractionDefect(plugin.name, procName,
            fingerprint,
            (file: nfSite.filename, line: nfSite.line, column: nfSite.column),
            nil, nfCollectMockFingerprints(nfVerifier, plugin.name))
        spyBody
      else:
        respType(nfMockOpt.get.response).realize()
