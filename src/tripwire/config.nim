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
##   [firewall]
##     mode                 = "off" | "allow_list" | "deny_all"
##     allowed_domains      = [...]
##     allowed_processes    = [...]

import std/[os, options, tables, sequtils]
import parsetoml

type
  FirewallMode* = enum
    fmOff, fmAllowList, fmDenyAll

  FirewallConfig* = object
    mode*: FirewallMode
    allowedDomains*: seq[string]
    allowedProcesses*: seq[string]

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
    firewall: FirewallConfig(mode: fmOff),
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
  result = FirewallConfig(mode: fmOff)
  if t.hasKey("mode"):
    case t["mode"].getStr
    of "off": result.mode = fmOff
    of "allow_list": result.mode = fmAllowList
    of "deny_all": result.mode = fmDenyAll
    else: discard
  if t.hasKey("allowed_domains"):
    result.allowedDomains = t["allowed_domains"].getElems.mapIt(it.getStr)
  if t.hasKey("allowed_processes"):
    result.allowedProcesses = t["allowed_processes"].getElems.mapIt(it.getStr)

proc loadConfig*(path: Option[string]): TripwireConfig =
  ## Load a `TripwireConfig` from `path`. If `path.isNone`, returns
  ## `defaultConfig()`. Unknown keys / sections are ignored by design;
  ## per-plugin blocks are stashed verbatim as TomlValueRef.
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
  for pluginName in result.enabledPlugins:
    if toml.hasKey(pluginName):
      result.pluginOptions[pluginName] = toml[pluginName]
  if toml.hasKey("firewall"):
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
