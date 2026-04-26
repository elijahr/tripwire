## tripwire/timeline.nim — Timeline and Interaction operations.
import std/[tables, monotimes]
import ./types

proc record*(t: var Timeline, plugin: Plugin, procName: string,
             args: OrderedTable[string, string], response: MockResponse,
             site: tuple[file: string, line, column: int]): Interaction {.raises: [].} =
  ## Append a mock-matched (G2-relevant) interaction to the timeline.
  ## The user is expected to assert via `responded()` / DSL /
  ## `markAsserted` before sandbox teardown, otherwise
  ## `UnassertedInteractionsDefect` fires.
  ##
  ## For firewall-passthrough recordings (where the user's
  ## `allow(plugin, M(...))` IS the assertion) the intercept
  ## combinators set `kind = ikFirewallPassthrough` via a tiny
  ## post-record mutation — see `tagFirewallPassthrough` below.
  result = Interaction(
    sequence: t.nextSeq, plugin: plugin, procName: procName,
    args: args, response: response, asserted: false,
    kind: ikMockMatched,
    site: site, createdAt: getMonoTime())
  inc(t.nextSeq)
  t.entries.add(result)

proc tagFirewallPassthrough*(i: Interaction) {.inline, raises: [].} =
  ## Re-tag a freshly-`record`ed Interaction as a firewall passthrough.
  ## Called by the intercept combinators (`tripwireInterceptBody` /
  ## `tripwirePluginIntercept`) when no mock matched: the call IS
  ## passing through under an `allow` rule, so it's not subject to
  ## Guarantee 2.
  ##
  ## Split out from a `kind`-parameter on `record` to keep the
  ## TRM-body call shape unchanged: under Nim 2.2.8 refc +
  ## unittest2's `failingOnExceptions` macro pipeline, adding an
  ## argument to `record`'s call site inside a {.dirty.} TRM body
  ## crashes the rewriter (vmgen internal error 1821,23 — same
  ## failure fingerprint as the whole-module-export issue documented
  ## in `auto_internal_exports.nim`'s "Why not whole-module
  ## re-exports" comment). A separate post-record `tag*` proc avoids
  ## touching `record`'s arg list at the TRM call site.
  i.kind = ikFirewallPassthrough

iterator unasserted*(t: Timeline): Interaction =
  ## Yields entries that are subject to Guarantee 2 (mock-matched
  ## recordings) and have not yet been marked asserted. Firewall
  ## passthroughs are not subject to G2 — the user already authorized
  ## the call via `allow(plugin, M(...))`, which IS the assertion. So
  ## passthroughs are filtered out here regardless of their `asserted`
  ## flag.
  for e in t.entries:
    if e.kind == ikFirewallPassthrough: continue
    if not e.asserted: yield e

proc markAsserted*(t: var Timeline, i: Interaction) =
  i.asserted = true
