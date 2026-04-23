## Target 3a: std/osproc.execProcess — TRM declares only the `command: string`
## parameter, hoping defaults are filled in by the compiler before match.
import std/osproc

var rewriteCount {.global.} = 0

template rewriteExecProcess{execProcess(command)}(command: string): string =
  inc(rewriteCount)
  "FAKE"

let s = execProcess("true")
echo "s=", s, " rewriteCount=", rewriteCount
