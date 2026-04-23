## tests/test_osproc_plugin.nim — F7: osproc plugin execProcess + execCmdEx.
import std/[unittest, osproc, options, tables]
import tripwire/[types, errors, timeline, sandbox, verify, intercept]
import tripwire/plugins/osproc as nfosp

# Wrapper procs — TRM-in-test gotcha (see test_mock_expect.nim docstring).
proc doExecProcess(cmd, workingDir: string, args: seq[string]): string =
  execProcess(cmd, workingDir, args)

proc doExecCmdEx(cmd: string): tuple[output: string, exitCode: int] =
  execCmdEx(cmd)

suite "osproc plugin":
  setup:
    while currentVerifier() != nil:
      discard popVerifier()

  test "plugin registered":
    check osprocPluginInstance != nil
    check osprocPluginInstance.name == "osproc"

  test "execProcess with seq[string] args is intercepted":
    sandbox:
      let v = currentVerifier()
      let args: seq[string] = @["arg1", "arg2"]
      let m = newMock("execProcess",
        fingerprintExecProcess("ls", "/tmp", args, nil,
          {poStdErrToStdOut, poUsePath, poEvalCommand}),
        OsprocExecProcessResponse(output: "fake-output\n", exitCode: 0),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(v, "osproc", m)
      let got = doExecProcess("ls", "/tmp", args)
      check got == "fake-output\n"
      v.timeline.markAsserted(v.timeline.entries[0])

  test "execCmdEx returns named tuple":
    sandbox:
      let v = currentVerifier()
      let m = newMock("execCmdEx",
        fingerprintExecCmdEx("echo hi",
          {poStdErrToStdOut, poUsePath}, nil, "", ""),
        OsprocExecCmdExResponse(output: "hi\n", exitCode: 0),
        (filename: "t.nim", line: 1, column: 0))
      registerMock(v, "osproc", m)
      let (output, code) = doExecCmdEx("echo hi")
      check output == "hi\n"
      check code == 0
      v.timeline.markAsserted(v.timeline.entries[0])
