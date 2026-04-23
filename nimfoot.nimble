# Package

version       = "0.1.0"
author        = "nimfoot contributors"
description   = "Test mocking framework with three-guarantee enforcement"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0"
requires "parsetoml >= 0.7.0"

# Tasks

task test, "Run the full test matrix":
  # refc + sync
  exec "nim c --gc:refc --define:nimfootActive --import:nimfoot/auto -r tests/all_tests.nim"
  # orc + sync
  exec "nim c --gc:orc --define:nimfootActive --import:nimfoot/auto -r tests/all_tests.nim"
  # refc + unittest2
  exec "nim c --gc:refc --define:nimfootActive --define:nimfootUnittest2 --import:nimfoot/auto -r tests/all_tests.nim"
  # orc + unittest2
  exec "nim c --gc:orc --define:nimfootActive --define:nimfootUnittest2 --import:nimfoot/auto -r tests/all_tests.nim"
  # test_osproc_arrays.nim runs standalone — aggregating its wrappers into
  # all_tests.nim pushes cap_counter's 15-rewrite cap (Defense 3).
  exec "nim c --gc:orc --define:nimfootActive -r tests/test_osproc_arrays.nim"
  # orc + chronos — opt-in via env var because chronos isn't in `requires`.
  # Set NIMFOOT_TEST_CHRONOS=1 to enable; otherwise skip the chronos cell.
  if existsEnv("NIMFOOT_TEST_CHRONOS"):
    exec "nim c --gc:orc --define:nimfootActive --define:chronos --import:nimfoot/auto -r tests/all_tests.nim"

task test_fast, "Run one config for quick iteration":
  exec "nim c --gc:orc --define:nimfootActive --import:nimfoot/auto -r tests/all_tests.nim"

task test_defenses, "Run the Defense-1 compile-fail check":
  # NimScript has no execShellCmd; gorgeEx returns (output, exitCode).
  let r = gorgeEx("nim c --dry-run tests/fixtures/defense1_probe.nim")
  doAssert r.exitCode != 0, "Defense 1 did not fire as expected"
