## tests/test_config.nim — B1 TDD suite for tripwire/config.nim.

import std/[unittest, os, options, tables]
import tripwire/config

suite "config":
  test "defaultConfig has empty enabled plugins and builtin source":
    let c = defaultConfig()
    check c.enabledPlugins.len == 0
    check c.sources == @["builtin-defaults"]
    check c.allowPendingAsync == false

  test "loadConfig with fixture reads enabled_plugins":
    let path = currentSourcePath().parentDir / "fixtures" / "tripwire.toml"
    let c = loadConfig(some(path))
    check c.enabledPlugins == @["mock", "httpclient"]
    check c.allowPendingAsync == true
    check "builtin-defaults" in c.sources
    check path in c.sources

  test "loadConfig parses plugin options":
    let path = currentSourcePath().parentDir / "fixtures" / "tripwire.toml"
    let c = loadConfig(some(path))
    check c.pluginOptions.hasKey("httpclient")

  test "loadConfig parses [tripwire.firewall] block":
    let path = currentSourcePath().parentDir / "fixtures" / "tripwire.toml"
    let c = loadConfig(some(path))
    check c.firewall.allow == @["mock"]
    check c.firewall.guard == fgWarn

  test "TRIPWIRE_CONFIG missing file raises":
    putEnv("TRIPWIRE_CONFIG", "/nonexistent/path.toml")
    expect ValueError:
      discard discoverConfigPath()
    delEnv("TRIPWIRE_CONFIG")

  test "loadConfig(none) returns defaults with single source":
    let c = loadConfig(none(string))
    check c.sources == @["builtin-defaults"]
    check c.enabledPlugins.len == 0
