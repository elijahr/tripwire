## tripwire/tests/test_firewall_reserved_keys.nim - convention enforcement.
##
## The [tripwire.firewall] TOML schema reserves `default` and `allow` as
## sibling keys with non-plugin meanings. A plugin whose Plugin.name string
## collides with one of these would produce a silent parser misroute (the
## per-plugin lookup at intercept.outsideSandboxShouldPassthrough would
## never find the entry, because parseFirewallConfig routes the value to
## fc.default or fc.allow first). Caught at CI time here.

import std/unittest
import tripwire/plugins/[
  mock, httpclient, chronos_httpclient, osproc, websock]

const ReservedFirewallKeys = ["default", "allow", "guard"]

suite "firewall reserved-key enforcement":
  test "no plugin shadows a reserved [tripwire.firewall] sibling key":
    # One assertion per plugin instance so a failure pinpoints the
    # offending plugin. Each check independent; do NOT short-circuit.
    check mockPluginInstance.name notin ReservedFirewallKeys
    check httpclientPluginInstance.name notin ReservedFirewallKeys
    check chronosHttpPluginInstance.name notin ReservedFirewallKeys
    check osprocPluginInstance.name notin ReservedFirewallKeys
    check websockPluginInstance.name notin ReservedFirewallKeys
