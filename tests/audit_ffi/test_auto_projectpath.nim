## tests/audit_ffi/test_auto_projectpath.nim — WI1 Task 1.2 acceptance.
##
## Asserts the v0.2 direct-scope auto-discovery contract introduced by
## Task 1.2 (design §5.2 and §5.2.1):
##
##   Case A: compiling `src/tripwire/audit_ffi.nim` with
##           `-d:tripwireAuditFFI` AND NO env vars set emits an audit
##           hint whose body references the project path
##           (`querySetting(projectPath)`, i.e. the directory of
##           `audit_ffi.nim` itself when it's the compile target).
##           The emission MUST NOT mention the v0.1 env-var contract
##           — v0.2 has eliminated the env-var mechanism (WI1 v0.1
##           baseline note, design §5.6 breaking change).
##
##   Case B: Emission shape contract. Pins the v0.1-compatible report
##           structure (Direct FFI header, `Direct total:` line,
##           Transitive placeholder, Grand total footer) so future
##           changes can't silently break consumers that grep the
##           build log. This case does NOT exercise the F3
##           empty-projectPath branch in `scanProjectPath`: F3 is
##           unreachable under regular `nim c` invocation because the
##           compiler always resolves `querySetting(projectPath)` to
##           the main compile target's directory, and there is no CLI
##           knob to clear it. F3 is defensive code against future
##           Nim versions or NimScript-driven compiles; its shape
##           parity with the happy path is a design invariant
##           (§5.2), not something this test verifies.
##
## Task 1.2 scope explicitly DEFERS the transitive-scope section to
## Task 1.4. For now the report emits a placeholder
## `Transitive FFI: 0 (not scanned -- set -d:tripwireAuditFFITransitive
## to enable)`. Case A asserts this placeholder so the shape contract
## (direct + transitive sections, grand total) stays intact for v0.1
## consumers.
##
## Strategy mirrors `tests/test_audit_ffi.nim`: shell out to `nim c
## --compileOnly` in a child process with `-d:tripwireAuditFFI` and
## capture the compiler's hint stream. `--compileOnly` is required
## because `nim check` skips `staticExec` (compiler/vmops.nim ~L282),
## and the audit's shell-driven scan lives inside `staticExec`.
##
## The `auditCmdNoEnv` template deliberately does NOT prepend any
## `env VAR=...` clause for the removed v0.1 env-var contract — that
## is the load-bearing assertion: the scan runs WITHOUT any env var
## input (design §5.6).

import std/[unittest, osproc, strutils, os]

const RepoRoot = currentSourcePath().parentDir().parentDir().parentDir()
const SrcPath = RepoRoot / "src"
const AuditTarget = RepoRoot / "src" / "tripwire" / "audit_ffi.nim"
const ExpectedProjectPath = RepoRoot / "src" / "tripwire"
  ## `querySetting(projectPath)` returns the directory containing the
  ## main compile-target `.nim` file. When that target is
  ## `src/tripwire/audit_ffi.nim`, projectPath resolves to
  ## `<repo>/src/tripwire`. Verified empirically on Nim 2.2.6.

template auditCmdNoEnv(): string =
  ## Build the nim invocation line for the audit scan with NO env var
  ## input. If any future code path re-introduces the removed env-var
  ## mechanism (design §5.6), this template's environment will NOT
  ## set any such variable, so the test captures only the
  ## querySetting-driven behavior.
  "nim c --compileOnly --hints:on --path:" & quoteShell(SrcPath) &
    " -d:tripwireAuditFFI " & quoteShell(AuditTarget) & " 2>&1"

suite "audit_ffi auto-projectpath (Task 1.2)":
  test "direct scan uses querySetting(projectPath), NOT env var":
    # Case A happy path: querySetting(projectPath) auto-discovers the
    # scan target. No v0.1 env-var is set in the test env (design §5.6).
    let cmd = auditCmdNoEnv()
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0: echo output
    check code == 0
    # Header is stable text emitted once per compile when the audit
    # runs. Byte-identical to v0.1 header to preserve v0.1 consumers
    # that grep the build log for this string.
    check "tripwire FFI audit (Defense 2 Part 3)" in output
    # Project path appears in the Direct FFI header line. This is the
    # core assertion: the scan's target dir is the querySetting
    # result, not a hardcoded "src" or an env-var value. We pin the
    # full `Direct FFI (paths: <projectPath>)` form so the check
    # isn't satisfied by the Nim compiler's own `proj: ...` path
    # echo in the hint preamble.
    check ("Direct FFI (paths: " & ExpectedProjectPath & ")") in output
    # Negative assertion: v0.2 must not mention the retired v0.1
    # env-var contract (design §5.6). The checked substring below is
    # the common prefix of the removed env-var names; a match would
    # leak from either an accidentally preserved doc-comment mention
    # or a regressed code path that still reads the removed env vars.
    check "TRIPWIRE_FFI_" notin output

  test "report shape: direct section + transitive placeholder + grand total":
    # Case B pins the v0.1-compatible emission shape (Direct FFI
    # header + Direct total + Transitive placeholder + Grand total).
    # Does NOT cover the F3 empty-projectPath branch -- F3 is
    # unreachable under `nim c` (see module docstring).
    let cmd = auditCmdNoEnv()
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0: echo output
    check code == 0
    # Direct section present.
    check "Direct FFI" in output
    check "Direct total:" in output
    # Transitive section: Task 1.2 defers transitive scope to Task
    # 1.4, so the emission is a placeholder keyed on the new define
    # flag. The placeholder MUST NOT leak the old env-var name.
    check "Transitive FFI: 0 (not scanned" in output
    check "-d:tripwireAuditFFITransitive" in output
    # Grand total footer preserved from v0.1 shape. We don't pin a
    # specific integer here because the fixture dir for this test is
    # `<repo>/src/tripwire` itself — any future FFI pragma (or
    # doc-comment pragma-syntax reference that FFIPragmaRegex
    # intentionally does NOT filter) added to that tree would
    # legitimately change the total. What MUST hold is that the
    # grand total equals the direct total, since transitive is
    # deferred to Task 1.4 and emits 0.
    let directTotalLine = block:
      var found = ""
      for ln in output.splitLines:
        let s = ln.strip()
        if s.startsWith("Direct total:"):
          found = s
          break
      found
    check directTotalLine.len > 0
    let directN = directTotalLine["Direct total:".len .. ^1].strip()
    check ("Grand total: " & directN) in output
