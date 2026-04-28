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
##     default              = "warn" | "error"        # default "error"
##     <plugin-name>        = "warn" | "error"        # per-plugin override
##
## Bigfoot pedigree
## ----------------
## The `[tripwire.firewall]` block is modeled on bigfoot's
## `[tool.bigfoot.firewall]` (axiomantic/bigfoot, the Python library
## tripwire ports). The per-key form (`default = "..."` plus per-plugin
## sibling keys) mirrors bigfoot's `[tool.bigfoot.firewall]` exactly;
## bigfoot's `guard = "warn"` default is replaced here with `default =
## "error"` for safer-by-default tripwire behavior. Uses the unified
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
    default*: FirewallMode ## default mode for plugins not in `guards`
    guards*: Table[string, FirewallMode]
      ## per-plugin override map; keyed by `Plugin.name`. A lookup miss
      ## falls back to `default`. Bigfoot-parity sibling-key form.

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
    firewall: FirewallConfig(allow: @[], default: fmError,
                             guards: initTable[string, FirewallMode]()),
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

var legacyGuardWarned {.threadvar.}: bool

proc parseFirewallModeStr(label, raw: string): FirewallMode
    {.raises: [ValueError].} =
  case raw
  of "warn": fmWarn
  of "error": fmError
  else:
    raise newException(ValueError,
      "[tripwire.firewall]." & label & " must be \"warn\" or \"error\"; got: " &
      raw)

proc parseFirewallModeStrOrFallback(label, raw: string): FirewallMode
    {.raises: [].} =
  ## Variant used by the TOML parser. A bad mode string is operator
  ## error, but it must NOT crash config loading: the
  ## "config-load failure must not mask the underlying violation"
  ## contract documented in `parseFirewallConfig` requires that a
  ## malformed firewall section degrades gracefully to the default
  ## `fmError` mode (the safer disposition — unmocked calls raise)
  ## with a one-line stderr breadcrumb so the operator can correct
  ## the file. Returning the strict-mode fallback also matches the
  ## behavior consumers see when there is no `tripwire.toml` at all.
  try:
    parseFirewallModeStr(label, raw)
  except ValueError as e:
    try:
      stderr.writeLine("tripwire: ignoring malformed " &
        "[tripwire.firewall]." & label & "=" & raw &
        " (" & e.msg & "); falling back to error mode")
    except IOError:
      discard
    fmError

proc parseFirewallConfig(t: TomlValueRef): FirewallConfig =
  ## Parse a `[tripwire.firewall]` (or legacy `[firewall]`) table. Keys:
  ##   - `allow` -> `seq[string]` of blanket-allowed plugin names.
  ##   - `default` -> top-level FirewallMode for plugins not otherwise
  ##     keyed.
  ##   - any other string-valued sibling key -> per-plugin entry stored
  ##     in `guards[key]`. Plugin name canonicalization is exact (sync
  ##     `httpclient` and async `chronos_httpclient` are separate keys).
  ##   - non-string siblings (e.g., future subtables under
  ##     `[tripwire.firewall]`) are silently ignored - forward-compat.
  ##   - A string-valued sibling literally named `guard` triggers a
  ##     one-time stderr warning at the first parse encounter (legacy
  ##     A4'''.4 key, renamed to `default` in A4'''.5); the value is
  ##     still stored in `guards` for forward-compat but never consulted.
  result = FirewallConfig(allow: @[], default: fmError,
                          guards: initTable[string, FirewallMode]())
  # parsetoml API dependency: `t.tableVal[]` dereferences a
  # `TomlTableRef = ref OrderedTable[string, TomlValueRef]` exposed by
  # parsetoml. Verified at parsetoml 0.7.2 against the worktree at tip
  # 07db4f3. A bump to a newer parsetoml requires re-verifying that the
  # `for k, v in t.tableVal[]:` iteration shape still type-checks and
  # yields per-key (string, TomlValueRef) pairs.
  #
  # Defensive guard: `t` is the value at key `[tripwire.firewall]` /
  # `[firewall]`. parsetoml will return whatever TOML structure the user
  # wrote there - if a user wrote `firewall = "warn"` (a scalar) instead
  # of a table, `t.tableVal[]` would raise FieldDefect / AssertionDefect
  # and short-circuit firewall config loading entirely. Returning the
  # empty default here preserves the "config-load failure must NOT mask
  # the underlying [...] violation" contract documented in
  # `intercept.outsideSandboxShouldPassthrough` (the operator should see
  # the LeakedInteractionDefect first; fix the sandbox issue and then
  # fix any config-file syntax issue separately).
  if t.kind != TomlValueKind.Table: return result
  for k, v in t.tableVal[]:
    case k
    of "allow":
      # Type-guard the array container AND every element. parsetoml's
      # `getElems`/`getStr` assert (AssertionDefect) on wrong-typed
      # values, which would crash the process on a malformed
      # `tripwire.toml` like `allow = "plugin"` (string instead of
      # array) or `allow = ["x", 123]` (mixed). Silent ignore is
      # consistent with the "non-string siblings silently ignored"
      # rule below and the "config-load failure must NOT mask the
      # underlying violation" contract documented above.
      if v.kind == TomlValueKind.Array:
        for elem in v.getElems:
          if elem.kind == TomlValueKind.String:
            result.allow.add(elem.getStr)
    of "default":
      # Type-guard before `getStr`. `default = 123` (int) would
      # otherwise crash on the assertion inside `getStr`.
      if v.kind == TomlValueKind.String:
        result.default = parseFirewallModeStrOrFallback("default", v.getStr)
    else:
      if v.kind == TomlValueKind.String:
        if k == "guard" and not legacyGuardWarned:
          try:
            stderr.writeLine("tripwire: ignoring legacy " &
              "[tripwire.firewall].guard key (renamed to `default` in " &
              "A4'''.5; treated as per-plugin override for plugin name " &
              "'guard', which does not exist)")
          except IOError:
            discard
          legacyGuardWarned = true
        result.guards[k] = parseFirewallModeStrOrFallback(k, v.getStr)
      # Non-string siblings silently ignored (forward-compat for subtables).

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
  if result.firewall.allow.len == 0 and
     result.firewall.default == fmError and
     result.firewall.guards.len == 0 and
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
  legacyGuardWarned = false
