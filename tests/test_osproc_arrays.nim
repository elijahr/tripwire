## tests/test_osproc_arrays.nim — F8: array-variant + openArray fallback.
##
## Validates that `execProcess(cmd, workingDir, args)` with a fixed-size
## array container matches a dedicated array TRM (arrays 0..8 are emitted
## via macro), and that any container not covered by seq/array routes to
## the openArray fallback trap, which raises UnmockableContainerDefect.
import std/[unittest, osproc, strtabs, options, tables]
import nimfoot/[types, errors, timeline, sandbox, verify, intercept]
import nimfoot/plugins/osproc as nfosp

# Wrapper procs — TRM-in-test gotcha (see test_mock_expect.nim docstring).
# The wrapper forces stdlib default elaboration at the wrapper call site,
# giving the TRM pattern matcher a concrete call shape to match against.
proc doExecProcessArray2(cmd, workingDir: string,
                         args: array[2, string]): string =
  execProcess(cmd, workingDir, args)

proc doExecProcessArray0(cmd, workingDir: string,
                         args: array[0, string]): string =
  execProcess(cmd, workingDir, args)

# Fallback trigger wrapper — takes a seq plus slice bounds so the
# `toOpenArray` view is constructed inside the wrapper's scope (where
# the openArray fallback TRM pattern sees a concrete call shape).
proc doExecProcessSlice(cmd, workingDir: string, src: seq[string],
                        lo, hi: int): string =
  execProcess(cmd, workingDir, toOpenArray(src, lo, hi))

suite "osproc array variants + fallback":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "execProcess with array[2, string] args is intercepted":
    sandbox:
      let v = currentVerifier()
      let args: array[2, string] = ["a", "b"]
      let m = newMock("execProcess",
        fingerprintExecProcess("ls", "", @["a", "b"], nil,
          {poStdErrToStdOut, poUsePath, poEvalCommand}),
        OsprocExecProcessResponse(output: "arr-ok", exitCode: 0),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(v, "osproc", m)
      let got = doExecProcessArray2("ls", "", args)
      check got == "arr-ok"
      v.timeline.markAsserted(v.timeline.entries[0])

  test "execProcess with empty array[0, string] args":
    sandbox:
      let v = currentVerifier()
      let args: array[0, string] = []
      let m = newMock("execProcess",
        fingerprintExecProcess("ls", "", @[], nil,
          {poStdErrToStdOut, poUsePath, poEvalCommand}),
        OsprocExecProcessResponse(output: "empty", exitCode: 0),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(v, "osproc", m)
      let got = doExecProcessArray0("ls", "", args)
      check got == "empty"
      v.timeline.markAsserted(v.timeline.entries[0])

  test "fallback trap fires for toOpenArray slice (Defense 5)":
    ## Confirms execProcessOpenArrayFallbackTRM catches calls whose args
    ## arrive as a `toOpenArray` view — neither seq nor array[0..8]. The
    ## TRM raises UnmockableContainerDefect rather than attempting to
    ## canonicalize an unknown container shape silently.
    sandbox:
      let src: seq[string] = @["x", "y", "z"]
      var raised = false
      try:
        discard doExecProcessSlice("ls", "", src, 0, 1)
      except UnmockableContainerDefect:
        raised = true
      check raised
