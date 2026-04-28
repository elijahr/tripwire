## tripwire/auto.nim — umbrella TRM module (Task G1).
##
## This module is the activation gateway for tripwire. Consumer projects
## inject it into every test compilation unit via their test config.nims:
##
## ```nim
## --import:"tripwire/auto"
## --define:"tripwireActive"
## ```
##
## The `--import` flag causes Nim to add `import tripwire/auto` to every
## translation unit, which transitively imports every plugin module.
## Each plugin's module-init code calls `registerPlugin(...)` against
## the global registry, and their TRM templates become in-scope for
## pattern matching across the TU.
##
## Gated by `-d:tripwireActive`: when the define is absent, this module
## compiles to a no-op. This lets tripwire modules be referenced in a
## project without accidentally activating TRM emission (e.g., when
## tooling parses the source tree without the test-config flags).
##
## See design doc §5 (activation model) and §10 Defense 1 (the facade
## guards `import tripwire` with a compile-time error when `tripwireActive`
## is absent, pointing users at this umbrella).
when defined(tripwireActive):
  # Importing the plugin modules is sufficient to register them: each
  # plugin's module-init code runs `registerPlugin(...)` against the
  # global registry, and the plugin's TRM templates become in-scope in
  # every TU that has this umbrella in its import graph (which is every
  # TU when Nim's `--import:"tripwire/auto"` flag is set).
  import ./plugins/mock
  import ./plugins/httpclient
  import ./plugins/osproc
  # Chronos httpclient firewall (G1-only). Auto-registers when chronos is
  # in scope; consumers without chronos see no plugin and no compile cost.
  # See plugins/chronos_httpclient.nim for the firewall-only rationale.
  when defined(chronos):
    import ./plugins/chronos_httpclient
  # Websock client firewall (G1-only). Auto-registers when the consumer
  # opts in via `-d:websock`; consumers without websock see no plugin
  # and no compile cost. See plugins/websock.nim for the firewall-only
  # rationale (mirror of the chronos plugin shape).
  when defined(websock):
    import ./plugins/websock as websock_plugin

  # Re-export the plugin modules (not just import them). Without this,
  # the TRM expansion at consumer sites that only do `import tripwire/auto`
  # type-checks `spyBody` in a different scope than direct
  # `import tripwire/plugins/httpclient` would, and Nim 2.2.8 emits
  # spurious "expression has to be used or discarded" errors in the
  # generated TRM body. The empirical fix is to surface the plugin
  # modules in the consumer's import graph by name, the same way a
  # direct import would.
  export mock, httpclient, osproc
  when defined(chronos):
    export chronos_httpclient
  when defined(websock):
    export websock_plugin

  # Re-export the focused set of framework symbols that the
  # `{.dirty.}` TRM combinator's body references at expansion time.
  # See `auto_internal_exports.nim` for the rationale (Nim 2.2.8's
  # `bind` clause does not reach proc symbols inside TRM-target
  # `{.dirty.}` templates, so we have to make them lookup-resolvable
  # at the call site).
  import ./auto_internal_exports
  export auto_internal_exports
else:
  discard
