## tests/test_cap_counter.nim — Defense 3 (D2) probes.
##
## Two probes:
##   1. Compile-fail probe: the fixture `cap_overflow.nim` must NOT compile
##      because it calls `nimfootCountRewrite` 16 times (cap is 15).
##   2. Compile-success probe: 15 calls must compile clean.
##
## Both probes shell out to `nim check` because the counter is per
## compilation unit — running the checks inside the main test process
## would pollute its own counter.
import std/[unittest, os, osproc, strutils]

const FixturePath = "tests/fixtures/cap_overflow.nim"

suite "cap counter (Defense 3)":
  test "compile-fail probe fires at 16 rewrites":
    # `nim check` is a type/semantic check without codegen; plenty to trip
    # the {.error.} in cap_counter.nim. `2>&1` folds stderr into stdout
    # so we can match either stream.
    let cmd = "nim check --hints:off --warnings:off " & FixturePath & " 2>&1"
    let (output, code) = execCmdEx(cmd)
    check code != 0
    check "nimfoot: more than 15 TRM rewrites" in output

  test "15 rewrites in one file compile clean":
    # Embed 15 calls in a tempfile and run `nim check`. Using an absolute
    # path via `getTempDir()` avoids CWD ambiguity across shells.
    let src = """
import nimfoot/cap_counter
""" & "nimfootCountRewrite()\n".repeat(15)
    let tmp = getTempDir() / "nf_cap_ok.nim"
    writeFile(tmp, src)
    defer: removeFile(tmp)
    # The tempfile is outside the tests dir; pass --path:src explicitly
    # because config.nims' `--path:"../src"` is relative to tests/.
    let cmd = "nim check --hints:off --warnings:off --path:src " & tmp
    let (output, code) = execCmdEx(cmd)
    if code != 0:
      echo output
    check code == 0
