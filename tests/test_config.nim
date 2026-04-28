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
    check c.firewall.default == fmWarn

  test "TRIPWIRE_CONFIG missing file raises":
    putEnv("TRIPWIRE_CONFIG", "/nonexistent/path.toml")
    expect ValueError:
      discard discoverConfigPath()
    delEnv("TRIPWIRE_CONFIG")

  test "loadConfig(none) returns defaults with single source":
    let c = loadConfig(none(string))
    check c.sources == @["builtin-defaults"]
    check c.enabledPlugins.len == 0

  test "malformed [tripwire.firewall] keys do not crash the parser":
    # Regression guard: a wrong-typed `allow` (string instead of array)
    # or `default` (int instead of string) used to crash via
    # parsetoml's getElems/getStr asserts (AssertionDefect). The
    # parser now type-guards each key and silently ignores
    # wrong-typed values, consistent with the "config-load failure
    # must NOT mask the underlying violation" contract.
    let tmp = getTempDir() / "tripwire-malformed.toml"
    writeFile(tmp, """
[tripwire.firewall]
allow = "not-an-array"
default = 123
mock = "warn"
""")
    defer: removeFile(tmp)
    # MUST NOT raise.
    let c = loadConfig(some(tmp))
    # Wrong-typed `allow` → empty.
    check c.firewall.allow.len == 0
    # Wrong-typed `default` → unchanged (builtin default fmError).
    check c.firewall.default == fmError
    # Per-plugin override survives because it's a valid string.
    check c.firewall.guards.getOrDefault("mock", fmError) == fmWarn

