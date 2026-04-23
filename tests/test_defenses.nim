## tests/test_defenses.nim — probes for compile-time defense gates.
##
## Currently covers Defense 1 (G2): `import nimfoot` must fail with a
## clear {.error.} when the consumer forgot to activate nimfoot via
## `--import:"nimfoot/auto" --define:"nimfootActive"` in their test
## config. The escape hatch `-d:nimfootAllowInactive` must suppress
## the error for tooling that references nimfoot symbols without
## wiring up TRM activation.
##
## The probes shell out to `nim check` so the guard's compile-time
## error terminates the subprocess, not the main test binary.
import std/[unittest, osproc, strutils]

const FixturePath = "tests/fixtures/defense1_probe.nim"

suite "Defense 1: facade activation guard (G2)":
  test "D1: importing nimfoot without flags fails at compile time":
    let cmd = "nim check --hints:off --warnings:off " & FixturePath & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    check code != 0
    check "nimfoot was imported but not activated" in output

  test "D1: -d:nimfootAllowInactive suppresses the error":
    let cmd = "nim check --hints:off -d:nimfootAllowInactive " &
      FixturePath & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    check code == 0

  test "D1: -d:nimfootActive (the activation path) also suppresses":
    # Sanity check: the intended happy path (user set nimfootActive)
    # must also compile clean.
    let cmd = "nim check --hints:off -d:nimfootActive " &
      FixturePath & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0:
      echo output
    check code == 0

  test "facade exposes the full public API surface":
    # The fixture imports nimfoot and also references symbols that
    # live in the core modules (types, errors, sandbox, etc.). If the
    # facade fails to re-export them, `nim check` on the fixture with
    # `-d:nimfootActive` will error with `undeclared identifier`.
    const SurfacePath = "tests/fixtures/facade_surface.nim"
    let cmd = "nim check --hints:off -d:nimfootActive " &
      SurfacePath & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0:
      echo output
    check code == 0
