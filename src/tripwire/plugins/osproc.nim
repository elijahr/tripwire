## tripwire/plugins/osproc.nim — std/osproc interception.
##
## Intercepts `execProcess` and `execCmdEx`. Fake `Process` scaffolding
## (TripwireFakeProcessTag + thread-local `fakeProcessTags`) supports F8's
## `startProcess` fake-Process variant.
##
## TRMs route through `tripwirePluginIntercept` (untyped respType) rather
## than `tripwireInterceptBody` — see plugins/plugin_intercept.nim.

import std/[osproc, strtabs, tables, options, macros]
import ../[types, registry, timeline, sandbox, verify, intercept, errors]
import ./plugin_intercept

export plugin_intercept.tripwirePluginIntercept

type
  OsprocPlugin* = ref object of Plugin
  OsprocExecProcessResponse* = ref object of MockResponse
    output*: string
    exitCode*: int
  OsprocExecCmdExResponse* = ref object of MockResponse
    output*: string
    exitCode*: int
  OsprocStartProcessResponse* = ref object of MockResponse
    mockId*: int
    exitCode*: int
    output*: string
    stderr*: string

  TripwireFakeProcessTag* = object
    ## Thread-local record attached to a fake Process pid, consumed by
    ## Process-state accessors (waitForExit, peekExitCode, etc) in F8.
    mockId*: int
    expectedExit*: int
    expectedOutput*: string
    expectedStderr*: string

method realize*(r: OsprocExecProcessResponse): string {.base.} = r.output

method realize*(r: OsprocExecCmdExResponse): tuple[output: string, exitCode: int] {.base.} =
  (output: r.output, exitCode: r.exitCode)

# Thread-local tag table for fake Processes (F8 populates on startProcess).
var fakeProcessTags* {.threadvar.}: Table[int, TripwireFakeProcessTag]

let osprocPluginInstance* = OsprocPlugin(name: "osproc", enabled: true)
registerPlugin(osprocPluginInstance)

proc fingerprintExecProcess*(cmd, workingDir: string, args: seq[string],
    env: StringTableRef, options: set[ProcessOption]): string =
  ## Canonicalize the six interesting fields into a stable fingerprint.
  ## env stringifies as "nil" when absent.
  fingerprintOf("execProcess",
    @[cmd, workingDir, $args,
      (if env.isNil: "nil" else: $env), $options])

proc fingerprintExecCmdEx*(cmd: string, options: set[ProcessOption],
    env: StringTableRef, workingDir, input: string): string =
  fingerprintOf("execCmdEx",
    @[cmd, $options,
      (if env.isNil: "nil" else: $env), workingDir, input])

# ---- execProcess seq[string] TRM ----------------------------------------
template execProcessSeqTRM*{execProcess(cmd, workingDir, args, env, options)}(
    cmd: string, workingDir: string = "",
    args: seq[string] = @[],
    env: StringTableRef = nil,
    options: set[ProcessOption] = {poStdErrToStdOut, poUsePath, poEvalCommand}): string =
  tripwirePluginIntercept(
    osprocPluginInstance,
    "execProcess",
    fingerprintExecProcess(cmd, workingDir, args, env, options),
    OsprocExecProcessResponse):
    {.noRewrite.}:
      execProcess(cmd, workingDir, args, env, options)

# ---- execCmdEx TRM -------------------------------------------------------
# Note: execCmdEx's stdlib default is {poStdErrToStdOut, poUsePath}, NOT
# {poStdErrToStdOut, poUsePath, poEvalCommand} like execProcess. Fingerprints
# in user tests must match the stdlib default otherwise the TRM fires but
# finds no mock. Pattern-var names (c, o, e, w, i) are distinct from
# execProcessSeqTRM's (cmd, workingDir, args, env, options) purely for
# readability and to avoid any identifier overlap between the two TRMs.
# `realExecCmdEx` is a private alias to the stdlib `osproc.execCmdEx` proc.
# Used as the passthrough call inside `execCmdExTRM`'s spy body. The
# `{.noRewrite.}` pragma is supposed to suppress further TRM matching on
# the inner call, but under Nim 2.2.8 it silently fails for this specific
# TRM (the call inside the `{.noRewrite.}` block re-matches `execCmdExTRM`,
# producing unbounded recursive expansion that trips the cap counter).
# Routing through a renamed procvar makes the call site a non-`execCmdEx`
# symbol so the TRM pattern matcher cannot match it. Confirmed against
# 2.2.8 with `nim --version` 2.2.8 [MacOSX: arm64].
let realExecCmdEx*: proc(command: string, options: set[ProcessOption],
                         env: StringTableRef, workingDir, input: string):
                           tuple[output: string, exitCode: int]
                         {.gcsafe, raises: [IOError, OSError, Exception].} =
  osproc.execCmdEx
  ## Exported because the `{.dirty.}` `tripwirePluginIntercept` template
  ## inlines its `spyBody` (which references this symbol) at every TRM
  ## call site in the consumer TU. The symbol must be reachable from
  ## those sites; an unexported `let` inside the plugin module would not
  ## resolve there even though `--import:"tripwire/auto"` pulls the
  ## module into the import graph.

template execCmdExTRM*{execCmdEx(c, o, e, w, i)}(
    c: string,
    o: set[ProcessOption] = {poStdErrToStdOut, poUsePath},
    e: StringTableRef = nil, w: string = "",
    i: string = ""): tuple[output: string, exitCode: int] =
  tripwirePluginIntercept(
    osprocPluginInstance,
    "execCmdEx",
    fingerprintExecCmdEx(c, o, e, w, i),
    OsprocExecCmdExResponse):
    {.noRewrite.}:
      realExecCmdEx(c, o, e, w, i)

# ---- F8: execProcess array variants 0..8 --------------------------------
# stdlib's execProcess declares `args: openArray[string] = []`. Fixed-size
# arrays pass through this openArray, but Nim TRM matching treats `seq` and
# `array[N, string]` as distinct call shapes. Emit a dedicated TRM per
# small arity (0..8) so common inline-array usage is intercepted without
# the user converting to `@args`. Arities >8 fall through to the fallback
# trap at the bottom, which tells the user how to proceed (wrap with `@`).
macro emitExecProcessArrayVariants(maxN: static[int]): untyped =
  ## Pattern vars are built via `ident` (not bare names inside `quote do:`)
  ## so they reach the AST un-gensym'd. With gensym'd names the template
  ## pattern `{execProcess(cmd, ...)}` fails to match the call — Nim
  ## 2.2.6's TRM engine compares pattern-var symbols to the template's
  ## formal-param symbols, and gensym breaks that linkage. Confirmed via
  ## isolated repro; see test_osproc_arrays.nim.
  result = newStmtList()
  let cmdI = ident"cmd"
  let wdI = ident"workingDir"
  let argsI = ident"args"
  let envI = ident"env"
  let optsI = ident"options"
  for n in 0 .. maxN:
    let tmplName = ident("execProcessArrayTRM" & $n)
    let arrayTy = nnkBracketExpr.newTree(
      ident"array", newLit(n), ident"string")
    let tdef = quote do:
      template `tmplName`*{execProcess(`cmdI`, `wdI`, `argsI`, `envI`,
                                        `optsI`)}(
          `cmdI`: string, `wdI`: string = "",
          `argsI`: `arrayTy`,
          `envI`: StringTableRef = nil,
          `optsI`: set[ProcessOption] = {poStdErrToStdOut, poUsePath,
                                          poEvalCommand}): string =
        tripwirePluginIntercept(
          osprocPluginInstance,
          "execProcess",
          fingerprintExecProcess(`cmdI`, `wdI`, @(`argsI`), `envI`, `optsI`),
          OsprocExecProcessResponse):
          {.noRewrite.}:
            execProcess(`cmdI`, `wdI`, `argsI`, `envI`, `optsI`)
    result.add(tdef)

emitExecProcessArrayVariants(8)

# ---- F8: Defense 5 — openArray fallback trap (MUST be last) -------------
# If seq + arrays 0..8 all missed, the user passed a container shape we
# cannot canonicalize (typically a `toOpenArray` slice or an array with
# arity > 8). Raise UnmockableContainerDefect pointing the user to wrap
# args with `@` to force a seq. Registration ORDER matters: Nim 2.2.6
# tries TRMs in declaration order, so this MUST be emitted after the
# seq TRM and the array-variant macro.
template execProcessOpenArrayFallbackTRM*{
    execProcess(cmd, workingDir, args, env, options)}(
    cmd: string, workingDir: string = "",
    args: openArray[string],
    env: StringTableRef = nil,
    options: set[ProcessOption] = {poStdErrToStdOut, poUsePath,
                                    poEvalCommand}): string =
  # Body must have a `string` value for type-check, but the raise
  # unconditionally transfers control before the sentinel is produced.
  # A trailing "" satisfies the type-checker; the `UnreachableCode` hint
  # at the call site is expected and benign.
  block:
    tripwireCountRewrite()
    raise newUnmockableContainerDefect(
      procName = "execProcess",
      containerType = "openArray[string] (unknown concrete container)",
      site = instantiationInfo())
    ""
