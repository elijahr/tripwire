## nimfoot/macros.nim — shared DSL keywords + AST helpers for plugin authors.
##
## The user-visible DSL verbs (`respond`, `responded`, `request`) are declared
## as `{.dirty.}` templates so plugin-specific `expect` macros can inspect and
## re-emit the body in the caller's scope. This module carries only the
## plugin-agnostic primitives. `expect` itself is declared in each plugin
## (F1: MockPlugin, F4: httpclient) because each plugin's `expect` must emit
## plugin-specific `registerMock` calls.
##
## `inAnyOrder` lives in `nimfoot/context.nim` (Task A3.5), not here.
import std/macros
import ./[types, sandbox]

# ---- DSL keyword dirty templates ----------------------------------------
template respond*(body: untyped) {.dirty.} =
  ## DSL verb used inside `expect`: declares the response to a mocked call.
  ## Dirty so the body's identifiers bind in the caller's scope, letting
  ## plugin macros inspect the AST.
  body

template responded*(body: untyped) {.dirty.} =
  ## DSL verb used inside `assert`: declares the expected response that
  ## was produced by a recorded interaction.
  body

template request*(body: untyped) {.dirty.} =
  ## DSL verb used inside `assert`: declares the expected request
  ## fields (e.g. `method`, `url`) on a recorded interaction.
  body

# ---- AST helpers for plugin authors -------------------------------------
proc procReturnType*(call: NimNode): NimNode =
  ## Extract the return type from a resolved proc symbol call.
  ##
  ## `call[0]` is the proc symbol; `getTypeImpl` returns an nnkProcTy whose
  ## first child is the formalParams node and whose first child in turn is
  ## the return type AST.
  let procSym = call[0]
  let impl = getTypeImpl(procSym)
  expectKind(impl, nnkProcTy)
  impl[0][0]

proc argsFingerprintAST*(call: NimNode): NimNode =
  ## Generate AST: `fingerprintOf(<procName>, @[$arg0, $arg1, ...])`.
  ##
  ## `call[0]` is the proc symbol and `call[1..]` are the positional args.
  ## Each arg is stringified via `$` so plugin-declared `expect` macros
  ## produce the same fingerprint shape regardless of arg type.
  let procNameStr = newLit($call[0])
  var rendered = nnkBracket.newTree()
  for i in 1 ..< call.len:
    rendered.add(newCall("$", call[i]))
  result = newCall("fingerprintOf", procNameStr, prefix(rendered, "@"))

# ---- Per-compilation-unit TRM emission registry -------------------------
# Tracks which user procs already have a TRM emitted in the current
# compilation unit. Plugin `expect` macros consult this so multiple
# `expect foo(...)` calls in a test share a single TRM, avoiding the
# per-hloBody rewrite cap (Defense 3 addresses the cap itself).
var emittedTRMs {.compileTime.}: seq[string] = @[]

proc hasEmittedTRM*(procName: string): bool {.compileTime.} =
  ## Returns true if a TRM for `procName` has already been emitted in
  ## the current compilation unit.
  procName in emittedTRMs

proc markTRMEmitted*(procName: string) {.compileTime.} =
  ## Record that a TRM for `procName` has been emitted. Idempotent: a
  ## second call with the same name is a no-op so plugin macros can
  ## mark without first checking.
  if procName notin emittedTRMs:
    emittedTRMs.add(procName)
