## tests/test_firewall_raises_compat.nim — regression guard:
## firewall TRM expansion must compose with chronos `async: (raises: [...])`.
##
## ## What this file pins
##
## paperplanes (and any future consumer) declares chronos httpclient
## procs with strict raises clauses, e.g.:
##
##   proc post(...): Future[T] {.async: (raises: [HttpError, CancelledError]).}
##
## Inside such a proc, every call must be raises-compatible — the
## compiler refuses to type-check the body if any callee can leak a
## CatchableError type that isn't in the declared raises set.
##
## The chronos plugin's `tripwirePluginIntercept` TRM expands a body
## that calls into tripwire's firewall hot path: `popMatchingMock`,
## `firewallShouldRaise`, `emitFirewallWarning`, etc. Historically those
## raised KeyError (table access) and IOError (stderr.writeLine), which
## broke compilation at every consumer call site that lived inside a
## strict-raises async proc.
##
## ## What this test asserts (compile-time only)
##
## Compilation success IS the test. The body declares a chronos
## `async: (raises: [...])` proc that calls `httpclient.send` and
## `httpclient.fetch` — both intercepted by the chronos plugin's TRMs.
## If the firewall hot path leaks any CatchableError, this file will
## fail to type-check with the same error paperplanes hits:
##
##   tripwire/src/tripwire/plugins/plugin_intercept.nim(NN, NN) Error:
##   popMatchingMock(...) can raise an unlisted exception: ref KeyError
##
## ## Why this file is its own standalone cell
##
## The chronos plugin's two firewall TRMs each count toward Defense 3's
## 15-rewrites-per-compilation-unit cap. Co-locating with
## `test_chronos_httpclient_firewall.nim` (which already exercises the
## same TRMs) would push the aggregate over. Standalone is precedent
## (see test_osproc_arrays.nim, test_firewall.nim).
when defined(chronos):
  import std/[unittest, uri]
  import chronos
  import chronos/apps/http/[httpclient, httpcommon]
  import tripwire/[types, errors, sandbox, verify]
  import tripwire/plugins/chronos_httpclient as nfchronos

  # The TWO surfaces this test pins, mirrored from a typical consumer
  # (paperplanes' src/transport/http_real.nim:142). Each declares the
  # strictest-supported raises set for its chronos surface so any future
  # CatchableError leak in the firewall hot path breaks THIS file
  # before it breaks consumers.

  proc strictSendUser(req: HttpClientRequestRef):
      Future[HttpClientResponseRef] {.
        async: (raises: [CancelledError, HttpError]).} =
    ## Strict-raises caller of `httpclient.send`. The chronos plugin's
    ## `chronosSendTRM` rewrites this call site to expand
    ## `tripwirePluginIntercept`. If that expansion's body leaks any
    ## CatchableError outside `(CancelledError | HttpError)`, this proc
    ## fails to type-check.
    return await httpclient.send(req)

  proc strictFetchUser(session: HttpSessionRef, url: Uri):
      Future[HttpResponseTuple] {.
        async: (raises: [CancelledError, HttpError]).} =
    ## Strict-raises caller of `httpclient.fetch(session, url)`. Same
    ## firewall-TRM regression surface as `strictSendUser`.
    return await httpclient.fetch(session, url)

  suite "firewall raises compatibility":
    test "TRM body composes with chronos async (raises: [HttpError, CancelledError])":
      # Compilation alone is the test. Reaching this `discard` means
      # both `strictSendUser` and `strictFetchUser` type-checked
      # successfully — the firewall hot path no longer leaks
      # CatchableError into surrounding strict-raises async procs.
      check declared(strictSendUser)
      check declared(strictFetchUser)
