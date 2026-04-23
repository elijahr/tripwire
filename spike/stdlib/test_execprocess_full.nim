## Target 3b: std/osproc.execProcess — TRM declares all 5 params.
import std/osproc
import std/strtabs

var rewriteCount {.global.} = 0

template rewriteExecProcess{execProcess(command, workingDir, args, env, options)}(
    command: string, workingDir: string, args: openArray[string],
    env: StringTableRef, options: set[ProcessOption]): string =
  inc(rewriteCount)
  "FAKE"

## Pass all 5 explicitly; defaults not used.
let s = execProcess("true", "", ["-n"], nil, {poUsePath})
echo "s=", s, " rewriteCount=", rewriteCount
