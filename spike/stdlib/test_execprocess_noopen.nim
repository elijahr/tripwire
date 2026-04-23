## Target 3c: try execProcess with seq[string] instead of openArray[string]
## in the TRM parameter list, since openArray is a metatype.
import std/osproc
import std/strtabs

var rewriteCount {.global.} = 0

template rewriteExecProcess{execProcess(command, workingDir, args, env, options)}(
    command: string, workingDir: string, args: seq[string],
    env: StringTableRef, options: set[ProcessOption]): string =
  inc(rewriteCount)
  "FAKE"

let args = @["-n"]
let s = execProcess("true", "", args, nil, {poUsePath})
echo "s=", s, " rewriteCount=", rewriteCount
