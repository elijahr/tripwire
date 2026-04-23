import std/unittest
import nimfoot/[types, registry]

suite "registry":
  setup:
    clearRegistry()

  test "registerPlugin appends a plugin":
    let p = Plugin(name: "p1", enabled: true)
    registerPlugin(p)
    check pluginByName("p1") == p

  test "pluginByName returns nil for missing":
    check pluginByName("missing") == nil

  test "duplicate name REPLACES existing":
    let p1 = Plugin(name: "p1", enabled: true)
    let p2 = Plugin(name: "p1", enabled: false)
    registerPlugin(p1)
    registerPlugin(p2)
    check pluginByName("p1") == p2
    check pluginByName("p1").enabled == false

  test "enabledPlugins filters by enabled flag":
    let p1 = Plugin(name: "p1", enabled: true)
    let p2 = Plugin(name: "p2", enabled: false)
    registerPlugin(p1)
    registerPlugin(p2)
    let enabled = enabledPlugins()
    check enabled.len == 1
    check enabled[0] == p1
