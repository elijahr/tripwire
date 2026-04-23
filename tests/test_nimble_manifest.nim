## Acceptance test for A1: verifies the nimble manifest parses and
## declared deps are resolvable. Runs only by direct invocation.
import std/[os, osproc, strutils, unittest]

suite "nimble manifest":
  test "nimble tasks lists test, test_fast, test_defenses":
    let (output, code) = execCmdEx("nimble tasks")
    check code == 0
    check "test" in output
    check "test_fast" in output
    check "test_defenses" in output

  test "parsetoml dependency is declared":
    let manifest = readFile(getCurrentDir() / "nimfoot.nimble")
    check "parsetoml" in manifest
    check ">= 0.7.0" in manifest or ">=0.7.0" in manifest
