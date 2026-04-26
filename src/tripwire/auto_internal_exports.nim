## tripwire/auto_internal_exports.nim — focused re-exports for TRM expansion.
##
## Why this module exists
## ----------------------
## Plugin TRMs expand inline at the consumer's call site. Inside that
## expansion, the body of `tripwire/plugins/plugin_intercept.tripwirePluginIntercept`
## (a `{.dirty.}` template) calls framework procs by their unqualified name:
## `popMatchingMock`, `record`, `firewallShouldRaise`, `nfCollectMockFingerprints`,
## etc. Because the template is `{.dirty.}`, those identifiers are resolved
## in the **caller's** scope, not the template definition's scope. The
## `bind` clause inside the template is *supposed* to override that, but
## empirically (Nim 2.2.8) does not work reliably for proc symbols when
## the template is also a TRM target.
##
## Without this module, a consumer that does `import tripwire/auto` and
## nothing else (the documented entry point) gets compile errors like
## "attempting to call undeclared routine: 'popMatchingMock'" the first
## time their code triggers a plugin TRM.
##
## What we re-export
## -----------------
## Only the framework symbols that plugin_intercept.tripwirePluginIntercept's
## body actually references at expansion time. We deliberately do NOT
## re-export the full `tripwire/timeline`, `tripwire/verify`, etc. modules —
## those carry helper symbols (`registerMock`, `newMock`, …) that the test-
## author may have their own names for.
##
## What this means for consumers
## -----------------------------
## After this module, `import tripwire/auto` is sufficient for any sandbox
## body that touches a plugin-intercepted surface (`std/httpclient`, `std/osproc`,
## etc.). Consumers writing their own plugin TRMs still need direct imports
## to call e.g. `registerMock` themselves; that is by design.
##
## Symbol-name collision policy
## ----------------------------
## Re-exported names that could plausibly collide with consumer code (e.g.
## `record`, `realize`, `isSome`, `get`, `isNil`) all flow through here.
## Consumer code that defines its own `record`/`realize` overload at module
## scope must disambiguate via a fully qualified call (`mymodule.record(...)`).
## This is the same disambiguation rule that applies to any other symbol
## brought into scope by `--import:tripwire/auto`.

import ./[errors, sandbox, timeline, verify, cap_counter, intercept]
import ./plugins/plugin_intercept
import std/[options, tables]

# Symbol-level re-exports. The TRM body expansion at consumer sites
# resolves identifiers in the consumer's scope (because the combinator
# is `{.dirty.}`); under Nim 2.2.8, the `bind` clause inside the
# combinator does not reliably reach across to the framework procs,
# so they must be reachable at the call site by name.
#
# Why not whole-module re-exports? `export errors`, `export sandbox`,
# etc. would crash the Nim 2.2.8 compiler under refc + unittest2 with
# an `internal error: vmgen.nim(1821, 23)` on `failingOnExceptions`
# expansion (verified empirically — the symbols collide somewhere in
# the unittest2/codegen pipeline). Per-symbol re-export sidesteps it
# and also keeps consumer namespace pollution minimal.
export sandbox.currentVerifier, sandbox.firewallShouldRaise,
       sandbox.sandbox,
       sandbox.allow, sandbox.restrict, sandbox.guard, sandbox.M,
       sandbox.FirewallMode
export errors.TripwireDefect,
       errors.LeakedInteractionDefect,
       errors.PostTestInteractionDefect,
       errors.UnmockedInteractionDefect,
       errors.UnassertedInteractionsDefect,
       errors.UnusedMocksDefect,
       errors.newLeakedInteractionDefect,
       errors.newPostTestInteractionDefect,
       errors.newUnmockedInteractionDefect
export verify.popMatchingMock, verify.verifyAll
export sandbox.popVerifier, sandbox.pushVerifier, sandbox.newVerifier
export timeline.record
export cap_counter.tripwireCountRewrite
export plugin_intercept.nfRecordFingerprint
export intercept.nfCollectMockFingerprints
export intercept.realize
export options.isSome, options.isNone, options.get
export tables.initOrderedTable
