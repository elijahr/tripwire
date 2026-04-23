## Surface probe for Task G2's facade re-exports.
##
## This fixture imports `nimfoot` (the facade) and references a symbol
## from every module the facade is meant to re-export. `nim check`
## with `-d:nimfootActive` must succeed; if the facade drops a module
## from its export list, this file fails at compile time.
##
## Run via `nim check -d:nimfootActive tests/fixtures/facade_surface.nim`
## or through the `test_defenses` harness (which asserts exitCode == 0).
##
## The probe relies on `declared()` checks wrapped in `when` so a
## missing re-export surfaces as a clear `{.error.}` rather than a
## generic undeclared-identifier. Actual behavior is covered by the
## other test suites; this file is purely a facade-completeness probe.
import nimfoot

# ---- types -------------------------------------------------------------
when not declared(Plugin):           {.error: "facade missing Plugin".}
when not declared(Verifier):         {.error: "facade missing Verifier".}
when not declared(Interaction):      {.error: "facade missing Interaction".}
when not declared(Timeline):         {.error: "facade missing Timeline".}
when not declared(MockResponse):     {.error: "facade missing MockResponse".}
when not declared(Mock):             {.error: "facade missing Mock".}

# ---- errors ------------------------------------------------------------
when not declared(NimfootDefect):
  {.error: "facade missing NimfootDefect".}
when not declared(UnmockedInteractionDefect):
  {.error: "facade missing UnmockedInteractionDefect".}
when not declared(UnusedMocksDefect):
  {.error: "facade missing UnusedMocksDefect".}
when not declared(LeakedInteractionDefect):
  {.error: "facade missing LeakedInteractionDefect".}

# ---- sandbox / verify lifecycle ---------------------------------------
when not declared(sandbox):       {.error: "facade missing sandbox template".}
when not declared(newVerifier):   {.error: "facade missing newVerifier".}
when not declared(currentVerifier):
  {.error: "facade missing currentVerifier".}
when not declared(newMock):       {.error: "facade missing newMock proc".}
when not declared(verifyAll):     {.error: "facade missing verifyAll".}

# ---- intercept ---------------------------------------------------------
when not declared(nimfootInterceptBody):
  {.error: "facade missing nimfootInterceptBody".}

# ---- macros / DSL ------------------------------------------------------
when not declared(respond):       {.error: "facade missing respond".}
when not declared(responded):     {.error: "facade missing responded".}
when not declared(request):       {.error: "facade missing request".}

# ---- config ------------------------------------------------------------
when not declared(loadConfig):    {.error: "facade missing loadConfig".}

# ---- futures -----------------------------------------------------------
when not declared(makeCompletedFuture):
  {.error: "facade missing makeCompletedFuture".}

# ---- integration_unittest backend -------------------------------------
# `test` is the nimfoot-flavored test template; `check` and `suite`
# come from the re-exported std/unittest backend.
when not declared(test):          {.error: "facade missing nimfoot test".}
when not declared(check):
  {.error: "facade missing check (from unittest backend)".}
when not declared(suite):
  {.error: "facade missing suite (from unittest backend)".}
