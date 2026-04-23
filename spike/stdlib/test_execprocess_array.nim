## Probe: execProcess with array[N, string] in TRM — see if it's specifically
## openArray that fails, or any type that requires conversion.
import std/osproc
import std/strtabs

var rewriteCount {.global.} = 0

template rewriteExecProcess{execProcess(command, workingDir, args, env, options)}(
    command: string, workingDir: string, args: array[1, string],
    env: StringTableRef, options: set[ProcessOption]): string =
  inc(rewriteCount)
  "FAKE"

let s = execProcess("true", "", ["-n"], nil, {poUsePath})
echo "s=", s, " rewriteCount=", rewriteCount
