import std/unittest
import nimfoot/[types, registry]

# Registry ordering hazard:
#
# The global `pluginRegistry` is populated at module init time by each
# built-in plugin (mock, httpclient, osproc). Once G1's `auto.nim`
# umbrella is active, `--import:nimfoot/auto` imports all three plugins
# BEFORE any test suite runs. Nim's import-dedup then prevents the
# plugins from re-registering when later test files (test_mock_plugin,
# test_httpclient_plugin, test_osproc_plugin) import them.
#
# This suite deliberately clears the global registry in `setup` to
# exercise register/lookup semantics on a clean slate. If we do not
# restore the real plugins in `teardown`, the nil slot persists for
# the rest of the process and later suites (test_mock_plugin et al.)
# that look up plugins by name fail with segfault on nil deref.
#
# Snapshot the plugin seq before each test; restore after. This keeps
# the suite hermetic without reaching into plugin modules.

var savedRegistry: seq[Plugin]

suite "registry":
  setup:
    savedRegistry = enabledPlugins()
    # Also capture disabled ones via the full table walk; enabledPlugins
    # filters, which is fine for our set (all real plugins are enabled).
    clearRegistry()

  teardown:
    clearRegistry()
    for p in savedRegistry:
      registerPlugin(p)

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
