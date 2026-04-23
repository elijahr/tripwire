## tripwire/registry.nim — global plugin registry.
import ./types

var pluginRegistry {.global.}: seq[Plugin] = @[]

proc registerPlugin*(p: Plugin) =
  ## Idempotent: a duplicate-name registration replaces the existing.
  for i, existing in pluginRegistry:
    if existing.name == p.name:
      pluginRegistry[i] = p
      return
  pluginRegistry.add(p)

proc enabledPlugins*(): seq[Plugin] =
  result = @[]
  for p in pluginRegistry:
    if p.enabled: result.add(p)

proc pluginByName*(name: string): Plugin =
  for p in pluginRegistry:
    if p.name == name: return p
  nil

proc clearRegistry*() =
  ## Test-only: reset for setup blocks. Not exported via facade.
  pluginRegistry.setLen(0)
