## tests/test_self_three_guarantees.nim — the framework's existence proof.
##
## Each of the three tripwire guarantees is exercised end-to-end here; if
## any of them fails to fire the expected defect, the framework is broken
## and this file must fail the build. The happy-path test catches the
## inverse (false-positive) regression where teardown spuriously raises.
##
## The outer `suite`/`test` come from `std/unittest` (via the tripwire
## facade's re-export of `integration_unittest`). Inside those wrappers,
## `expect <Defect>:` is std/unittest's exception-matching form — which
## wins over tripwire's `expect(typed, untyped)` mock-registration macro
## because the argument is a type symbol, not a call expression (design
## §5.2.1 overload-resolution note).
##
## The facade re-exports core modules only; plugin DSL macros
## (`expectHttp`/`assertHttp` for httpclient) must be imported directly
## because `auto.nim` doesn't export plugin symbols — it only pulls the
## plugin modules in so their TRM templates become in-scope in every TU
## via `--import:"tripwire/auto"`.
import std/[httpclient, asyncdispatch, options, tables]
# The tripwire facade re-exports integration_unittest, which re-exports
# whichever backend is active (std/unittest by default, unittest2 under
# `-d:tripwireUnittest2`), minus its `test`/`suite` so the tripwire-
# wrapped forms win. The backend's `expect` / `check` / `suite` come
# through here. Importing std/unittest DIRECTLY in addition would
# create an ambiguous-call clash under the unittest2 matrix cell.
import tripwire
import tripwire/plugins/httpclient as nfhttp

suite "Three Guarantees — self-test":

  test "G1 (pre-authorization): unmocked call raises UnmockedInteractionDefect":
    expect UnmockedInteractionDefect:
      sandbox:
        let c = newHttpClient()
        discard c.get("http://example.com")

  test "G2 (assertion): mocked call not asserted raises UnassertedInteractionsDefect":
    expect UnassertedInteractionsDefect:
      sandbox:
        let c = newHttpClient()
        nfhttp.expectHttp get(c, "http://example.com"):
          respond:
            status: 200
            body: "ok"
        discard c.get("http://example.com")
        # no `assert` of the interaction → sandbox verifyAll raises.

  test "G3 (consumption): registered mock never consumed raises UnusedMocksDefect":
    expect UnusedMocksDefect:
      sandbox:
        let c = newHttpClient()
        nfhttp.expectHttp get(c, "http://example.com"):
          respond:
            status: 200
            body: "ok"
        # no call at all → UnusedMocksDefect.

  test "G1 fires for async httpclient calls":
    expect TripwireDefect:
      sandbox:
        let c = newAsyncHttpClient()
        let resp = waitFor c.get("http://example.com")
        discard resp

  test "no defect when all three guarantees met (anti-false-positive)":
    sandbox:
      let c = newHttpClient()
      nfhttp.expectHttp get(c, "http://a"):
        respond:
          status: 200
          body: "ok"
      let resp = c.get("http://a")
      check resp.status == "200"
      nfhttp.assertHttp get(c, "http://a"):
        responded:
          status: 200
    # If this test reports a defect, the sandbox teardown is regressing.

  test "nested sandbox: inner verifyAll surfaces first":
    # Outer sandbox wraps inner sandbox; inner has a missing assertion;
    # the defect raised must be the INNER verifier's (it runs first in
    # the inner sandbox's finally clause before control returns to the
    # outer sandbox's verifyAll).
    expect UnassertedInteractionsDefect:
      sandbox:  # outer
        sandbox:  # inner
          let c = newHttpClient()
          nfhttp.expectHttp get(c, "http://a"):
            respond:
              status: 200
              body: "ok"
          discard c.get("http://a")
          # no assert → inner verifier raises UnassertedInteractionsDefect.
