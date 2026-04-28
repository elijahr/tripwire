## tripwire/tests/test_firewall_reserved_keys.nim - convention enforcement.
##
## The [tripwire.firewall] TOML schema reserves `default`, `allow`, and the
## legacy `guard` key as sibling keys with non-plugin meanings. A plugin
## whose Plugin.name string collides with one of these would produce a
## silent parser misroute (the per-plugin lookup at
## intercept.outsideSandboxShouldPassthrough would never find the entry,
## because parseFirewallConfig routes the value to fc.default / fc.allow
## first, and `guard` is treated as a one-time-warned legacy key).
## Caught at CI time here.
##
## Import gating: `chronos_httpclient` and `websock` plugin modules
## unconditionally import their respective external packages (`chronos`,
## `websock`/`chronicles`), so they only compile when the matching
## `-d:chronos` / `-d:websock` define is active AND the package is
## installed. Cells 6/6b/6c/6d in `tripwire.nimble` opt into those
## defines (gated behind `TRIPWIRE_TEST_CHRONOS` / `TRIPWIRE_TEST_WEBSOCK`
## env vars), so this test runs the full plugin set under those cells
## and the always-installed subset (mock, httpclient, osproc) under the
## default cell.

import std/unittest
import tripwire/plugins/[mock, httpclient, osproc]
when defined(chronos):
  import tripwire/plugins/chronos_httpclient
when defined(websock):
  import tripwire/plugins/websock

const ReservedFirewallKeys = ["default", "allow", "guard"]

suite "firewall reserved-key enforcement":
  test "no plugin shadows a reserved [tripwire.firewall] sibling key":
    # One assertion per plugin instance so a failure pinpoints the
    # offending plugin. Each check independent; do NOT short-circuit.
    check mockPluginInstance.name notin ReservedFirewallKeys
    check httpclientPluginInstance.name notin ReservedFirewallKeys
    check osprocPluginInstance.name notin ReservedFirewallKeys
    when defined(chronos):
      check chronosHttpPluginInstance.name notin ReservedFirewallKeys
    when defined(websock):
      check websockPluginInstance.name notin ReservedFirewallKeys
