## nimfoot/integration_unittest.nim — `test:` / `suite:` wrapping the
## chosen unittest backend with nimfoot's verifier lifecycle.
##
## Purpose
## -------
## Consumer tests call `nimfoot.test "name":` and `nimfoot.suite "name":`.
## Each nimfoot `test:` body is wrapped (Defense 4 — try/finally lifecycle,
## per design §11) so that:
##   1. a fresh `Verifier` is pushed onto the thread-local stack on entry,
##   2. the body runs inside `try:` and, on normal completion, is checked
##      for pending async operations (Defense 6 — design §10),
##   3. `finally:` pops the verifier and calls `verifyAll`, which raises
##      `UnassertedInteractionsDefect` / `UnusedMocksDefect` if either
##      guarantee is violated.
##
## `verifyAllOnExit` is wired into the process via `addExitProc` the first
## time `test:` instantiates on a thread. It drains any verifier that was
## leaked across test boundaries (e.g. the body raised, the process is
## shutting down with the stack non-empty) and reports the leak on stderr
## rather than on the next test.
##
## Backend selection
## -----------------
## By default this module re-exports `std/unittest`. With
## `-d:nimfootUnittest2` it re-exports `unittest2` (see `unittest2`
## package on nimble). Both backends expose the same `suite` and `test`
## templates; our `test:` / `suite:` templates forward to whichever is
## active via the `backend` alias.
import std/exitprocs
import ./[sandbox, verify, errors, futures]

when defined(nimfootUnittest2):
  import unittest2 as backend
  const backendName* = "unittest2"
else:
  import std/unittest as backend
  const backendName* = "std/unittest"

# Re-export the backend EXCEPT its `test` and `suite` templates. Those
# are shadowed by nimfoot's own `test`/`suite` wrappers below — if both
# were visible, consumers writing bare `suite "x":` / `test "y":` would
# hit an ambiguous-call error (seen under `-d:nimfootUnittest2`). The
# nimfoot wrapper is the intended entry point; the backend's raw forms
# stay available as `backend.test` / `backend.suite` through the
# `backend` alias when callers need them (e.g., self-hosting tests).
export backend except test, suite

var exitHookRegistered {.threadvar.}: bool

proc verifyAllOnExit*() {.noconv.} =
  ## Drain any verifiers that were still on the stack when the process
  ## shuts down. Each verifier is popped (becomes inactive) and
  ## `verifyAll` is invoked; any Nimfoot defect is reported on stderr
  ## rather than re-raised, because exit procs must not raise.
  while verifierStack.len > 0:
    let v = popVerifier()
    try:
      v.verifyAll()
    except NimfootDefect as e:
      stderr.writeLine "nimfoot: unverified verifier '" & v.name &
        "' at exit - " & e.msg

template test*(name: string, body: untyped) =
  ## nimfoot `test:` wraps the backend's `test name:` block with a
  ## verifier push/pop + verifyAll lifecycle. Pending async operations at
  ## body end raise `PendingAsyncDefect` (suppressed by
  ## `-d:nimfootAllowPendingAsync`).
  ##
  ## **First-violation-wins semantics** (matches `sandbox:` in
  ## `nimfoot/sandbox.nim`): if the body raised, that defect IS the
  ## verification failure — pop the verifier but skip verifyAll so the
  ## original (more informative) defect isn't masked by a secondary
  ## UnassertedInteractionsDefect raised inside a `finally`.
  bind pushVerifier, popVerifier, newVerifier, hasPendingOperations,
    newPendingAsyncDefect, verifyAllOnExit, addExitProc,
    getCurrentException
  if not exitHookRegistered:
    addExitProc(verifyAllOnExit)
    exitHookRegistered = true
  backend.test name:
    let nfV = pushVerifier(newVerifier(name))
    try:
      body
      when not defined(nimfootAllowPendingAsync):
        if hasPendingOperations():
          raise newPendingAsyncDefect(name)
    finally:
      discard popVerifier()
      if getCurrentException() == nil:
        nfV.verifyAll()

template suite*(name: string, body: untyped) =
  ## Pass-through to the active backend's `suite`. Exists so `import
  ## nimfoot/integration_unittest` alone supplies both `test:` (nimfoot-
  ## lifecycle-wrapped) and `suite:` to consumer tests. The backend's
  ## raw `suite` is intentionally excluded from the re-export to avoid
  ## ambiguity; callers that need the unwrapped form can reach it via
  ## the `backend` alias.
  backend.suite name:
    body
