## nimfoot/plugins/osproc.nim — std/osproc interception.
##
## Intercepts `execProcess` and `execCmdEx`. Fake `Process` scaffolding
## (NimfootFakeProcessTag + thread-local `fakeProcessTags`) supports F8's
## `startProcess` fake-Process variant.
##
## TRMs route through `nimfootPluginIntercept` (untyped respType) rather
## than `nimfootInterceptBody` — see plugins/plugin_intercept.nim.

import std/[osproc, strtabs, tables, options]
import ../[types, registry, timeline, sandbox, verify, intercept, errors]
import ./plugin_intercept

export plugin_intercept.nimfootPluginIntercept

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

  NimfootFakeProcessTag* = object
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
var fakeProcessTags* {.threadvar.}: Table[int, NimfootFakeProcessTag]

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
  nimfootPluginIntercept(
    osprocPluginInstance,
    "execProcess",
    fingerprintExecProcess(cmd, workingDir, args, env, options),
    OsprocExecProcessResponse):
    {.noRewrite.}:
      execProcess(cmd, workingDir, args, env, options)

# ---- execCmdEx TRM -------------------------------------------------------
# Note the distinct pattern-var names (c, o, e, w, i) from the local
# params (cmd, options, env, workingDir, input). Using the exact same
# names as in execProcessSeqTRM's pattern triggers a spurious
# 'redefinition of nfVerifier' error during pattern registration — two
# TRMs in one module with identical pattern-var names seem to share an
# expansion scope at compile time. Distinct pattern-var names isolate
# the templates.
template execCmdExTRM*{execCmdEx(c, o, e, w, i)}(
    c: string,
    o: set[ProcessOption] = {poStdErrToStdOut, poUsePath},
    e: StringTableRef = nil, w: string = "",
    i: string = ""): tuple[output: string, exitCode: int] =
  nimfootPluginIntercept(
    osprocPluginInstance,
    "execCmdEx",
    fingerprintExecCmdEx(c, o, e, w, i),
    OsprocExecCmdExResponse):
    {.noRewrite.}:
      execCmdEx(c, o, e, w, i)
