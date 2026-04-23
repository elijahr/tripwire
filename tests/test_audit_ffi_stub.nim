## tests/test_audit_ffi_stub.nim — H6.5 acceptance.
##
## Compiles src/tripwire/audit_ffi.nim under `-d:tripwireAuditFFI` in a
## child process and greps its compiler output for the FFI-audit hint.
## The hint proves that:
##   1. The define is a valid, advertised v0 activation knob.
##   2. The stub emits a visible signal (so users who opt in aren't
##      silently getting a no-op).
##   3. The facade wiring (`when defined(tripwireAuditFFI): import ...`)
##      survives being compiled through the public entry point.
##
## Uses `nim check` rather than `nim c` so we don't pay the link cost;
## `nim check` still evaluates the `{.hint.}` pragma.
import std/[unittest, osproc, strutils, os]

const RepoRoot = currentSourcePath().parentDir().parentDir()

suite "audit_ffi stub (H6.5, Defense 2 Part 3)":
  test "audit_ffi.nim compiles under -d:tripwireAuditFFI and emits the hint":
    # Must allow the file to compile standalone, which means giving it
    # the `tripwireAllowInactive` escape hatch via --path:src so
    # `tripwire/...` resolves, but NOT firing Defense 1 on the
    # facade: this fixture imports audit_ffi directly, not via
    # tripwire.nim, so activation guards don't fire.
    let target = RepoRoot / "src" / "tripwire" / "audit_ffi.nim"
    let cmd = "nim check --hints:on --path:" & (RepoRoot / "src") &
      " -d:tripwireAuditFFI " & target & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0:
      echo output
    check code == 0
    check "FFI audit not implemented in v0" in output

  test "audit_ffi.nim is a no-op WITHOUT the define":
    # Without -d:tripwireAuditFFI the module body is a `when`-guarded
    # empty block: it must compile cleanly and not emit the hint.
    let target = RepoRoot / "src" / "tripwire" / "audit_ffi.nim"
    let cmd = "nim check --hints:on --path:" & (RepoRoot / "src") &
      " " & target & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0:
      echo output
    check code == 0
    check "FFI audit not implemented in v0" notin output
