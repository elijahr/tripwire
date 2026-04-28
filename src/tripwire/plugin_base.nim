## tripwire/plugin_base.nim — base methods plugins override.
## Declares the four {.base.} methods required by design §5.1/§3.3.
import std/tables
import ./types

method assertableFields*(p: Plugin, i: Interaction): seq[string] {.base, raises: [].} =
  ## Which fields on the Interaction can user assertions reference?
  ## Plugins (e.g. httpclient) override to return @["status", "body", ...].
  @[]

method formatInteraction*(p: Plugin, i: Interaction): string {.base, raises: [].} =
  ## One-line renderer used in verbose Defect messages.
  ##
  ## `raises: []` because called from `newUnmockedInteractionDefect`
  ## inside the firewall hot path. Plugin overrides MUST be raises-compatible.
  p.name & " " & i.procName

method formatError*(p: Plugin, i: Interaction, kind: string): string {.base.} =
  kind & " in " & p.name & "." & i.procName

method matches*(p: Plugin, i: Interaction,
                criteria: OrderedTable[string, string]): bool {.base.} =
  ## Used by `inAnyOrder` + user criteria. Default accepts every interaction
  ## (plugins override for argument-aware matching).
  true

method supportsPassthrough*(p: Plugin): bool {.base, raises: [].} = false
  ## Plugin-level blanket: when true, every call routed through this
  ## plugin is allowed to fall through to its real implementation.
  ## MockPlugin returns true; httpclient/osproc return false. Lives in
  ## plugin_base so `firewallDecide` (in `tripwire/sandbox`) can call
  ## it without inverting the import graph.
  ##
  ## `raises: []` is load-bearing — this method is consulted from the
  ## firewall hot path inside TRM expansions, which may sit inside
  ## chronos `async: (raises: [...])` procs. Plugin overrides MUST be
  ## raises-compatible.

method passthroughFor*(p: Plugin, procName: string): bool {.base, raises: [].} = false
  ## Plugin-level per-proc blanket. Consulted only when
  ## `supportsPassthrough` is true; lets a plugin gate passthrough on
  ## the procName (e.g. allow `getEnv` but not `setEnv`).
  ##
  ## See `supportsPassthrough` for the `raises: []` rationale.
