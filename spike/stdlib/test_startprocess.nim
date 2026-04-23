## Target 4: std/osproc.startProcess — returns owned(Process).
## Use seq[string] for args (openArray failed per target 3).
import std/osproc
import std/strtabs

var rewriteCount {.global.} = 0

template rewriteStart{startProcess(command, workingDir, args, env, options)}(
    command: string, workingDir: string, args: seq[string],
    env: StringTableRef, options: set[ProcessOption]): Process =
  inc(rewriteCount)
  Process(nil)

let args = @["-n"]
let p = startProcess("true", "", args, nil, {poUsePath})
echo "p.isNil=", p.isNil, " rewriteCount=", rewriteCount
