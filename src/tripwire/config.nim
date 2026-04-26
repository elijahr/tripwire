## tripwire/config.nim — tripwire.toml parsing + discovery.
##
## Discovery rules (in order):
##   1. `TRIPWIRE_CONFIG` env var, if set — must point to an existing file
##      (otherwise raises ValueError).
##   2. Walk up from `getCurrentDir()` looking for `tripwire.toml`.
##   3. Stop the walk at the first directory that contains a `.nimble` file
##      (package root). Return `none(string)` if no toml was found along
##      the way — `loadConfig(none)` produces the builtin defaults.
##
## Schema (v0):
##   [tripwire]
##     enabled_plugins      = ["name", ...]
##     allow_pending_async  = bool
##   [<plugin-name>]          # one block per plugin listed above
##     ... plugin-specific keys, stashed as TomlValueRef
##   [tripwire.firewall]
##     allow                = ["plugin-name", ...]    # blanket-allow these plugins
##     guard                = "warn" | "error"        # default "error"
##
## Bigfoot pedigree
## ----------------
## The `[tripwire.firewall]` block is modeled on bigfoot's
## `[tool.bigfoot.firewall]` (axiomantic/bigfoot, the Python library
## tripwire ports). `guard = "warn"` mirrors bigfoot's default; tripwire
## defaults to `"error"` instead. Uses the unified
## `firewall_types.FirewallMode` so the parsed config maps directly onto
## the sandbox-level enum without a parallel translation step.

import std/[os, options, tables, sequtils]
import parsetoml
import ./firewall_types
export firewall_types

type
  FirewallConfig* = object
    ## Project-wide firewall configuration parsed from
    ## `[tripwire.firewall]`. Code-level `sandbox.allow(...)` /
    ## `sandbox.restrict(...)` calls win over the file values
    ## (later-wins rule); this struct supplies the per-sandbox
    ## bootstrap.
    allow*: seq[string]    ## plugin-name shorthands, e.g. ["dns", "socket"]
    guard*: FirewallMode

  TripwireConfig* = object
    enabledPlugins*: seq[string]
    pluginOptions*: Table[string, TomlValueRef]
    firewall*: FirewallConfig
    allowPendingAsync*: bool
    sources*: seq[string]

proc defaultConfig*(): TripwireConfig =
  ## Builtin defaults — returned by `loadConfig(none)` and used as the
  ## starting point for `loadConfig(some path)` before overlaying the TOML.
  TripwireConfig(
    enabledPlugins: @[],
    pluginOptions: initTable[string, TomlValueRef](),
    firewall: FirewallConfig(allow: @[], guard: fmError),
    allowPendingAsync: false,
    sources: @["builtin-defaults"])

proc discoverConfigPath*(): Option[string] =
  ## Locate a `tripwire.toml` by walking up from cwd, stopping at the
  ## package root (directory with any `.nimble`). Honors `TRIPWIRE_CONFIG`.
  let envPath = getEnv("TRIPWIRE_CONFIG", "")
  if envPath.len > 0:
    if fileExists(envPath):
      return some(envPath)
    raise newException(ValueError,
      "TRIPWIRE_CONFIG set to '" & envPath & "' but file does not exist")
  var dir = getCurrentDir().absolutePath()
  while true:
    let tomlPath = dir / "tripwire.toml"
    if fileExists(tomlPath):
      return some(tomlPath)
    # Package root reached — stop without finding a toml.
    for _ in walkPattern(dir / "*.nimble"):
      return none(string)
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  none(string)

proc parseFirewallConfig(t: TomlValueRef): FirewallConfig =
  result = FirewallConfig(allow: @[], guard: fmError)
  if t.hasKey("allow"):
    result.allow = t["allow"].getElems.mapIt(it.getStr)
  if t.hasKey("guard"):
    let gotString = t["guard"].getStr
    case gotString
    of "warn": result.guard = fmWarn
    of "error": result.guard = fmError
    else:
      raise newException(ValueError,
        "[tripwire.firewall].guard must be \"warn\" or \"error\"; got: " &
        gotString)

proc loadConfig*(path: Option[string]): TripwireConfig =
  ## Load a `TripwireConfig` from `path`. If `path.isNone`, returns
  ## `defaultConfig()`. Unknown keys / sections are ignored by design;
  ## per-plugin blocks are stashed verbatim as TomlValueRef.
  ##
  ## The firewall section is read from either `[tripwire.firewall]`
  ## (preferred, bigfoot-style) or top-level `[firewall]` (legacy
  ## flatness; kept so existing tripwire.toml files don't break).
  if path.isNone:
    return defaultConfig()
  let toml = parsetoml.parseFile(path.get)
  result = defaultConfig()
  result.sources = @["builtin-defaults", path.get]
  if toml.hasKey("tripwire"):
    let n = toml["tripwire"]
    if n.hasKey("enabled_plugins"):
      result.enabledPlugins = n["enabled_plugins"].getElems.mapIt(it.getStr)
    if n.hasKey("allow_pending_async"):
      result.allowPendingAsync = n["allow_pending_async"].getBool
    if n.hasKey("firewall"):
      result.firewall = parseFirewallConfig(n["firewall"])
  for pluginName in result.enabledPlugins:
    if toml.hasKey(pluginName):
      result.pluginOptions[pluginName] = toml[pluginName]
  if result.firewall.allow.len == 0 and result.firewall.guard == fmError and
     toml.hasKey("firewall"):
    # Legacy flat [firewall] block — only consult if the bigfoot-style
    # nested form left defaults intact.
    result.firewall = parseFirewallConfig(toml["firewall"])

var configMemo {.threadvar.}: Option[TripwireConfig]

proc getConfig*(): TripwireConfig =
  ## Thread-local memoized accessor. First call runs discovery + parse;
  ## subsequent calls return the cached value.
  if configMemo.isNone:
    configMemo = some(loadConfig(discoverConfigPath()))
  configMemo.get

proc reloadConfig*() =
  ## Advanced: drop the memoized config so the next `getConfig()` re-reads.
  configMemo = none(TripwireConfig)
