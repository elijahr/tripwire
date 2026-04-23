## nimfoot/plugin_base.nim — base methods plugins override.
## Declares the four {.base.} methods required by design §5.1/§3.3.
import std/tables
import ./types

method assertableFields*(p: Plugin, i: Interaction): seq[string] {.base.} =
  ## Which fields on the Interaction can user assertions reference?
  ## Plugins (e.g. httpclient) override to return @["status", "body", ...].
  @[]

method formatInteraction*(p: Plugin, i: Interaction): string {.base.} =
  ## One-line renderer used in verbose Defect messages.
  p.name & " " & i.procName

method formatError*(p: Plugin, i: Interaction, kind: string): string {.base.} =
  kind & " in " & p.name & "." & i.procName

method matches*(p: Plugin, i: Interaction,
                criteria: OrderedTable[string, string]): bool {.base.} =
  ## Used by `inAnyOrder` + user criteria. Default accepts every interaction
  ## (plugins override for argument-aware matching).
  true
