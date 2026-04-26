## tripwire/firewall_types.nim - neutral home for FirewallMode.
##
## Hosts FirewallMode here so both sandbox.nim and config.nim can import
## it without creating a sandbox<->config import cycle. Imports nothing
## else from tripwire to keep the dependency graph acyclic.

type
  FirewallMode* = enum
    ## Disposition of unmocked-and-not-allowed calls.
    ##
    ## Used in two contexts:
    ##   * Per-Verifier (`Verifier.firewallMode`): inside-sandbox unmocked-call
    ##     disposition. `fmError` raises UnmockedInteractionDefect; `fmWarn`
    ##     emits a stderr warning and proceeds via passthrough.
    ##   * Project-wide (`FirewallConfig.guard`): outside-sandbox disposition
    ##     for unmocked TRM calls. `fmError` raises LeakedInteractionDefect;
    ##     `fmWarn` either passes through (plugin supports it) or raises
    ##     OutsideSandboxNoPassthroughDefect (plugin doesn't).
    ##
    ## Defaults to `fmError` in both contexts to preserve "every external call
    ## is pre-authorized" without explicit opt-in.
    fmError, fmWarn
