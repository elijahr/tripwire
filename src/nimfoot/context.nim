## nimfoot/context.nim — sandbox-scoped assertion context.
##
## Houses:
## - `assertionsOpen` thread-local counter (tracks live assert DSL blocks).
## - `inAssertBlock` template — guards against running an assertion DSL
##   inside a live sandbox body; final verification belongs to teardown.
## - `inAnyOrder` template — toggles `currentVerifier().context.inAnyOrderActive`
##   for the body, restoring on exit even on exception.
import ./[types, errors, sandbox]

var assertionsOpen* {.threadvar.}: int

template inAssertBlock*(body: untyped) =
  bind currentVerifier
  let nfV = currentVerifier()
  if nfV != nil and nfV.active:
    let nfSite = instantiationInfo()
    raise (ref AssertionInsideSandboxError)(
      msg: "assertion DSL invoked inside live sandbox; final verification " &
        "is performed by sandbox teardown. Move this assertion outside " &
        "the sandbox body, or use `assert` during teardown.",
      site: (file: nfSite.filename, line: nfSite.line, column: nfSite.column))
  inc(assertionsOpen)
  try:
    body
  finally:
    dec(assertionsOpen)

template inAnyOrder*(body: untyped) =
  bind currentVerifier
  let nfV = currentVerifier()
  doAssert nfV != nil, "inAnyOrder requires an active sandbox"
  let nfPrev = nfV.context.inAnyOrderActive
  nfV.context.inAnyOrderActive = true
  try:
    body
  finally:
    nfV.context.inAnyOrderActive = nfPrev
