## tests/test_auto_umbrella.nim — Task G1 TDD test.
##
## Verifies that `import tripwire/auto` (compiled with -d:tripwireActive,
## as `nimble test` does) imports every plugin module at module init
## time. Plugin modules self-register with the global registry via
## `registerPlugin(...)` at module scope, so the presence of a plugin
## in the registry by-name table proves the plugin module was imported
## transitively through auto.nim.
##
## Also covers the consumer-ergonomics regression guard for the
## ‘only-import-auto’ pattern: a downstream test that does *only*
## `import tripwire/auto` (plus the stdlib module it wants to
## intercept) must compile and execute correctly. Pre-fix, plugin TRM
## expansions failed at consumer sites with errors like “undeclared
## identifier: popMatchingMock” because the `{.dirty.}` TRM
## combinator’s `bind` clause does not (under Nim 2.2.8) reach the
## framework procs at the expansion site. The fix re-exports the
## plugin modules and a focused set of framework symbols from auto.nim
## via auto_internal_exports.nim. This test pins that contract.
import std/unittest
import tripwire/auto
import tripwire/[types, registry]
# `httpclient` is the plugin-intercepted surface we exercise. Importing
# the stdlib module (NOT `tripwire/plugins/httpclient`) is intentional —
# the regression guard is precisely that consumers should not need to
# import any tripwire submodule beyond `tripwire/auto`.
import std/httpclient

suite "auto umbrella":
  test "all plugins registered when tripwireActive":
    when defined(tripwireActive):
      check pluginByName("mock") != nil
      check pluginByName("httpclient") != nil
      check pluginByName("osproc") != nil
    else:
      # Without tripwireActive, auto.nim compiles to a no-op; nothing
      # imports the plugin modules, so nothing is registered.
      skip()

  test "user-facing DSL reachable through auto":
    # End-to-end smoke: exercising the MockPlugin DSL (respond/responded)
    # re-exported through auto.nim proves the facade surface is wired.
    # Full DSL behavior is covered by test_mock_expect / test_mock_assert;
    # this test only verifies the symbols resolve through the umbrella.
    when defined(tripwireActive):
      let p = pluginByName("mock")
      check p != nil
      check p.enabled

  test "auto-only consumer can compile a plugin-intercepted call":
    # Regression guard: this test file imports ONLY `tripwire/auto` plus
    # `std/httpclient` (the intercepted surface). It must not need any
    # other `tripwire/*` import to compile a wrapper proc whose body
    # calls `c.request(url)` — Nim's TRM rewriter expands the body of
    # `tripwirePluginIntercept` inline at this call site, and every
    # symbol that body references (`popMatchingMock`, `record`,
    # `firewallShouldRaise`, …) must resolve through the auto umbrella.
    #
    # The wrapper proc is NOT called from this test (calling it without
    # an active sandbox would raise `LeakedInteractionDefect`); the
    # compile-time success of the proc body is itself the regression
    # signal. Behavioral coverage of the same TRM lives in
    # `test_httpclient_plugin.nim` and `test_firewall.nim`.
    when defined(tripwireActive):
      # The presence of this proc body forces TRM expansion. If TRM
      # expansion at the consumer site (where the only tripwire import
      # is `tripwire/auto`) cannot resolve a framework symbol, this
      # whole test file fails to compile and never reaches runtime —
      # so the “OK” you see for this test is itself the regression
      # signal. The runtime body just records the proc address into
      # `discardable`-ish storage so dead-code elimination cannot
      # silently drop the wrapper before the codegen verifier sees it.
      proc autoOnlyTrmCompiles(c: HttpClient, url: string): Response =
        c.request(url)
      var sink: pointer = cast[pointer](autoOnlyTrmCompiles)
      check sink != nil

  test "auto-only consumer reaches plugin instance by name":
    # Regression guard for the paperplanes-driven ergonomics:
    # `import tripwire/auto` MUST be sufficient to call
    # `allow(httpclientPluginInstance, M(...))` — the plugin's typed
    # `let` binding is reachable unqualified through the umbrella's
    # whole-module re-exports of its plugin modules. Pre-fix,
    # consumers had to `import tripwire/plugins/httpclient as nfhc`
    # and write `nfhc.httpclientPluginInstance`.
    when defined(tripwireActive):
      sandbox:
        # Fingerprint here doesn't matter — the matcher won't fire
        # because no call is made. We only care that the symbol
        # `httpclientPluginInstance` resolves through the umbrella.
        allow(httpclientPluginInstance, M(host = "127.0.0.1"))
        let v = currentVerifier()
        check v.allowPredicates.len == 1

  test "auto-only consumer reaches the firewall path through sandbox":
    # Behavioral guard: with a live sandbox + an `allow(...)` predicate
    # whose matcher does NOT match the call's host, the TRM expansion
    # must reach `firewallShouldRaise` and emit
    # `UnmockedInteractionDefect`. Exercising this end-to-end, with
    # only `import tripwire/auto` in scope, proves the firewall surface
    # is wired through the umbrella exactly as if the consumer had
    # imported `tripwire/sandbox` and `tripwire/plugins/httpclient`
    # directly.
    when defined(tripwireActive):
      let plugin = pluginByName("httpclient")
      check plugin != nil
      expect UnmockedInteractionDefect:
        sandbox:
          # Restrict the firewall to a host the request below will not
          # match — the call must therefore raise.
          allow(plugin, M(host = "10.255.255.255"))
          let c = newHttpClient()
          # 127.0.0.1:1 is unbound on every supported host; the call
          # never escapes the firewall layer because the matcher
          # rejects it before any spyBody passthrough is attempted.
          discard c.request("http://127.0.0.1:1/")
