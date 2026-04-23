## nimfoot/plugins/mock.nim — generic user-proc mocking.
##
## Design §5.1 / §6: MockPlugin is the passthrough-by-default plugin that
## intercepts arbitrary user procs. The user interface is two-part:
##
##   * `mockable(fn)` at MODULE scope: emits a TRM matching `fn(a0, a1, ...)`
##     that routes through `nimfootPluginIntercept`. Must be invoked once
##     per mockable proc, alongside the user's own module-level code.
##
##   * `expect fn(args...): respond value: V` inside a test block:
##     registers a mock keyed by procName + arg fingerprint. Assumes the
##     module-scope TRM from `mockable(fn)` is already in scope.
##
## Rationale: Nim 2.2.6 TRMs are lexically scoped AND the matcher
## deduplicates by pattern-AST across sibling blocks, so a TRM emitted
## from inside a `test:` or `sandbox:` block does NOT reliably fire in
## sibling blocks (empirically: only the first block's TRM fires). The
## plan's original design had `expect` emit the TRM inline, which works
## for ONE-block tests but silently breaks any suite with >1 test against
## the same proc. Emitting the TRM at module scope — the same pattern
## every built-in plugin (httpclient, osproc) uses — sidesteps the issue.
import std/[tables, macros]
import ../[types, registry, timeline, sandbox, verify, intercept, plugin_base]
import ../macros as nfmacros
import ./plugin_intercept
export nfmacros.respond, nfmacros.responded, nfmacros.request
export plugin_intercept.nimfootPluginIntercept

type
  MockPlugin* = ref object of Plugin
  MockUserResponse*[T] = ref object of MockResponse
    returnValue*: T

proc realize*[T](r: MockUserResponse[T]): T = r.returnValue
  ## Not a method — Nim 2.2.6 multimethod dispatch doesn't support generic
  ## type parameters. Call sites use concrete T via the TRM body cast:
  ## `MockUserResponse[T](resp).realize()`.

method supportsPassthrough*(p: MockPlugin): bool = true
method passthroughFor*(p: MockPlugin, procName: string): bool = true

method assertableFields*(p: MockPlugin, i: Interaction): seq[string] =
  @["value"]

let mockPluginInstance* = MockPlugin(name: "mock", enabled: true)
registerPlugin(mockPluginInstance)

# ---- F2: `mockable` + `expect` DSL --------------------------------------
# `mockable(fn)` emits a TRM at module scope (see module doc).
# `expect fn(...)` inside a test registers a mock; assumes module-scope TRM.

proc emitMockTRMFor(procSym: NimNode, args: seq[NimNode],
                    retType: NimNode): NimNode {.compileTime.} =
  ## Generate a TRM matching the user's proc signature. Each call-site arg
  ## is bound to a pattern variable a0, a1, ...
  let procName = $procSym

  # Build pattern-side call: procName(a0, a1, ...). The pattern must use
  # an `nnkIdent` (not `nnkSym`) so Nim's rewrite engine matches later
  # call sites where `procName` is still an unresolved identifier.
  let procIdent = newIdentNode(procName)
  var patternCall = nnkCall.newTree(procIdent)
  var formalParams = nnkFormalParams.newTree(retType)
  for i, arg in args:
    let aId = ident("a" & $i)
    patternCall.add(aId)
    # Use the arg's inferred type via getTypeInst on the call-site arg.
    formalParams.add(nnkIdentDefs.newTree(aId,
      getTypeInst(arg), newEmptyNode()))

  # Build body: nimfootInterceptBody(pluginInstance, procName,
  #   fingerprintOf(procName, @[$a0, $a1, ...]),
  #   MockUserResponse[retType],
  #   spyBody = {.noRewrite.}: procSym(a0, a1, ...))
  var renderedArgs = nnkBracket.newTree()
  for i in 0 ..< args.len:
    renderedArgs.add(newCall("$", ident("a" & $i)))

  # nimfootPluginIntercept(plugin, procName, fingerprint, respType, spyBody).
  # spyBody is the 5th positional arg. Wrap the real-proc invocation in a
  # {.noRewrite.} pragma block so the TRM does NOT match itself (Nim's
  # term-rewriting engine skips {.noRewrite.}-tagged subtrees).
  #
  # NOTE: We call `nimfootPluginIntercept` (from plugin_intercept.nim)
  # rather than `nimfootInterceptBody` (from intercept.nim) because the
  # latter declares `respType: typedesc`, which silently breaks TRM
  # pattern matching. See plugin_intercept.nim's module docstring for the
  # detailed analysis.
  let noRewritePragma = nnkPragma.newTree(ident"noRewrite")
  let spyBodyNode = nnkPragmaBlock.newTree(
    noRewritePragma,
    nnkStmtList.newTree(patternCall.copyNimTree))
  let body = newCall("nimfootPluginIntercept",
    ident"mockPluginInstance",
    newLit(procName),
    newCall("fingerprintOf", newLit(procName), prefix(renderedArgs, "@")),
    nnkBracketExpr.newTree(ident"MockUserResponse", retType),
    spyBodyNode)

  # Manual nnkTemplateDef with TRM pattern arm.
  # The TRM pattern lives at child index 1 (between name and genericParams),
  # wrapped in a StmtList. Layout for
  #   template name*{pattern}(params): ret = body
  # is (per dumpAstGen):
  #   [0] name (Postfix or Ident)
  #   [1] StmtList(pattern)
  #   [2] genericParams (empty)
  #   [3] formalParams
  #   [4] pragma (empty)
  #   [5] reserved (empty)
  #   [6] body
  # Non-dirty template: symbols in the body resolve at template-definition
  # site (here, inside plugins/mock). `nimfootInterceptBody`,
  # `mockPluginInstance`, `fingerprintOf`, and `MockUserResponse` are all
  # imported into this scope, so non-dirty binding works.
  let tmplName = genSym(nskTemplate, "mockTRM_" & procName)
  let tdef = nnkTemplateDef.newTree(
    tmplName,
    nnkStmtList.newTree(patternCall),  # TRM pattern arm
    newEmptyNode(),
    formalParams,
    newEmptyNode(),
    newEmptyNode(),
    body)
  result = newStmtList(tdef)

macro mockable*(call: typed): untyped =
  ## Module-scope declaration: `mockable(computeThing(0, 0))` emits a
  ## TRM at module scope so later `expect` calls register mocks that
  ## the TRM consumes.
  ##
  ## Usage (must be at top level of the caller's module):
  ##   proc computeThing(x, y: int): int = x + y
  ##   mockable(computeThing(0, 0))   # <- note: dummy args give the arity
  ##
  ## The arg values are ignored; only their types matter (for the TRM's
  ## formal parameter type inference).
  expectKind(call, nnkCall)
  let procSym = call[0]
  var callArgs: seq[NimNode]
  for i in 1 ..< call.len:
    callArgs.add(call[i])
  let retType = procReturnType(call)
  result = emitMockTRMFor(procSym, callArgs, retType)

macro expect*(call: typed, body: untyped): untyped =
  ## `expect fnName(args...): respond value: VALUE`
  ##
  ## Registers a Mock keyed by procName + arg fingerprint so the next
  ## matching call to `fnName(args...)` returns `VALUE`. Assumes
  ## `mockable(fnName(...))` was declared at module scope.
  ##
  ## The first param is `typed` (not `untyped`) so that `call[0]` is the
  ## resolved proc symbol — required for `getTypeImpl`-based return-type
  ## extraction. The `typed`-ness is also more specific than unittest's
  ## `expect(varargs[typed], untyped)`, resolving the overload collision
  ## in favour of this macro when both are imported.
  expectKind(call, nnkCall)
  let procSym = call[0]
  var callArgs: seq[NimNode]
  for i in 1 ..< call.len:
    callArgs.add(call[i])

  # Extract `respond value: VALUE` from body. The Nim parser represents
  # `respond value: 42` as:
  #   Command
  #     Ident "respond"
  #     Ident "value"
  #     StmtList (IntLit 42)
  # That is, the verb keyword is the 1st child, the "field" ident is the
  # 2nd, and the value expression is wrapped in a StmtList as the 3rd.
  var valueExpr: NimNode = nil
  for stmt in body:
    let isRespond = (stmt.kind in {nnkCommand, nnkCall}) and stmt.len >= 1 and
                    stmt[0].kind == nnkIdent and stmt[0].strVal == "respond"
    if not isRespond: continue
    # Walk the remaining children pairwise (fieldIdent, StmtList(value))
    var i = 1
    while i < stmt.len:
      let fieldNode = stmt[i]
      if fieldNode.kind == nnkIdent and fieldNode.strVal == "value" and
         i + 1 < stmt.len:
        let rhs = stmt[i + 1]
        if rhs.kind == nnkStmtList and rhs.len == 1:
          valueExpr = rhs[0]
        else:
          valueExpr = rhs
        break
      # Also support the ExprColonExpr form (single-line: `respond value: 42`
      # may in some layouts parse to `nnkExprColonExpr(value, 42)`).
      if fieldNode.kind == nnkExprColonExpr and
         fieldNode[0].kind == nnkIdent and fieldNode[0].strVal == "value":
        valueExpr = fieldNode[1]
        break
      inc i
    if valueExpr != nil: break
  if valueExpr == nil:
    error("expect ...: must contain `respond value: <expr>`. Got: " &
          body.treeRepr, body)

  # Resolve return type from the proc symbol.
  let retType = procReturnType(call)

  # Build: registerMock(currentVerifier(), "mock",
  #   newMock(procNameLit, fingerprintOf(procNameLit, @[$a, ...]),
  #           MockUserResponse[retType](returnValue: valueExpr),
  #           instantiationInfo()))
  var renderedArgs = nnkBracket.newTree()
  for a in callArgs:
    renderedArgs.add(newCall("$", a))
  let procNameLit = newLit($procSym)
  # Use nnkObjConstr to get `MockUserResponse[retType](returnValue: VALUE)`.
  # Plain `newCall` emits a regular call, which Nim rejects when a field
  # colon-expression appears as an argument.
  let respConstr = nnkObjConstr.newTree(
    nnkBracketExpr.newTree(ident"MockUserResponse", retType),
    nnkExprColonExpr.newTree(ident"returnValue", valueExpr))
  result = newCall("registerMock",
    newCall("currentVerifier"),
    newLit("mock"),
    newCall("newMock",
      procNameLit,
      newCall("fingerprintOf", procNameLit, prefix(renderedArgs, "@")),
      respConstr,
      newCall("instantiationInfo")))

macro assertMock*(call: typed, body: untyped): untyped =
  ## `assertMock fnName(args...): responded value: VALUE`
  ##
  ## Finds the next unasserted Interaction in the current verifier's
  ## timeline matching `fnName` (with passthrough-aware fingerprint),
  ## checks that its recorded `MockUserResponse[T].returnValue` equals
  ## `VALUE`, and marks the interaction asserted.
  ##
  ## Named `assertMock` rather than `assert` to avoid collision with the
  ## system `assert` template (overload resolution picks the wrong one).
  ##
  ## Raises `AssertionDefect` if no matching unasserted interaction exists
  ## or if the response value mismatches.
  expectKind(call, nnkCall)
  let procSym = call[0]
  var callArgs: seq[NimNode]
  for i in 1 ..< call.len:
    callArgs.add(call[i])

  # Extract `responded value: VALUE` from body. Parser shape:
  #   Command(Ident responded, Ident value, StmtList(VALUE))
  var valueExpr: NimNode = nil
  for stmt in body:
    let isResponded = (stmt.kind in {nnkCommand, nnkCall}) and stmt.len >= 1 and
                      stmt[0].kind == nnkIdent and stmt[0].strVal == "responded"
    if not isResponded: continue
    var i = 1
    while i < stmt.len:
      let fieldNode = stmt[i]
      if fieldNode.kind == nnkIdent and fieldNode.strVal == "value" and
         i + 1 < stmt.len:
        let rhs = stmt[i + 1]
        if rhs.kind == nnkStmtList and rhs.len == 1:
          valueExpr = rhs[0]
        else:
          valueExpr = rhs
        break
      if fieldNode.kind == nnkExprColonExpr and
         fieldNode[0].kind == nnkIdent and fieldNode[0].strVal == "value":
        valueExpr = fieldNode[1]
        break
      inc i
    if valueExpr != nil: break
  if valueExpr == nil:
    error("assertMock ...: must contain `responded value: <expr>`", body)

  let retType = procReturnType(call)
  var renderedArgs = nnkBracket.newTree()
  for a in callArgs:
    renderedArgs.add(newCall("$", a))
  let procNameLit = newLit($procSym)

  # Runtime:
  #   block:
  #     let v = currentVerifier()
  #     doAssert v != nil, "assertMock outside sandbox"
  #     let fp = fingerprintOf(procName, @[$a0, ...])
  #     var found: Interaction = nil
  #     for e in v.timeline.entries:
  #       if not e.asserted and e.procName == procName:
  #         found = e; break
  #     doAssert found != nil, "assertMock: no unasserted interaction for ..."
  #     let resp = MockUserResponse[retType](found.response)
  #     doAssert resp.returnValue == VALUE, "assertMock: response mismatch"
  #     v.timeline.markAsserted(found)
  result = quote do:
    block:
      let nfAV = currentVerifier()
      doAssert nfAV != nil, "assertMock outside sandbox"
      let nfAFp = fingerprintOf(`procNameLit`, @`renderedArgs`)
      var nfAFound: Interaction = nil
      for e in nfAV.timeline.entries:
        if not e.asserted and e.procName == `procNameLit` and
           ".fp" in e.args and e.args[".fp"] == nfAFp:
          nfAFound = e
          break
      doAssert nfAFound != nil,
        "assertMock: no unasserted interaction for " & `procNameLit` &
        " with fingerprint " & nfAFp
      let nfAResp = MockUserResponse[`retType`](nfAFound.response)
      doAssert nfAResp.returnValue == `valueExpr`,
        "assertMock: response mismatch for " & `procNameLit`
      nfAV.timeline.markAsserted(nfAFound)
