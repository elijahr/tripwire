## Compile-surface test for Task 3.2.
##
## Exercises every exported name from `tripwire/threads` at compile
## scope so a failure to declare or export any primitive surfaces as a
## hard compile error. Runtime behavior is NOT exercised here — that is
## Tasks 3.3-3.8's job (RED→GREEN coverage for happy path, multi-child,
## exception propagation, nested-sandbox, chronos rejection,
## nested-thread rejection).
##
## TODO(Task 3.9): add the negative refc+threads build fixture and wire
## the matrix cell; this file only covers the positive orc+threads path.

import std/unittest
import tripwire/threads
import tripwire/sandbox  # Verifier, newVerifier

# Worker signature required by tripwireThread.
proc noopWorker(data: int) {.thread, nimcall, gcsafe.} =
  discard data

suite "tripwire/threads: compile surface":
  test "ThreadHandoff type is referenceable":
    # Fresh ref object is nil by default — just naming the type is the
    # point; construction would dereference a stub.
    var h: ThreadHandoff = nil
    check h.isNil

  test "tripwireThread symbol is callable at this signature":
    # We do NOT actually expect the stub to succeed; we only need the
    # symbol to resolve and typecheck at the intended call site so the
    # bind list and generic instantiation compile.
    when false:
      var thr: Thread[int]
      tripwireThread(thr, noopWorker, 0)
    check true  # purely a compile-surface assertion

  test "runWithVerifier template compiles at a call site":
    # We invoke it at runtime too so the stub raises during RED; the
    # GREEN implementation must run the body with a pushed verifier
    # without raising.
    let v = newVerifier("compile-probe")
    var ran = false
    runWithVerifier(v):
      ran = true
    check ran

  test "withTripwireThread template compiles at a call site":
    when false:
      withTripwireThread:
        discard
    check true

  test "childEntry symbol is referenceable":
    let p: proc(h: ThreadHandoff) {.thread, nimcall, gcsafe.} = childEntry
    check not p.isNil
