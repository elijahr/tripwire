## tests/test_audit_ffi.nim — Defense 2 Part 3 acceptance.
##
## Exercises the real FFI-audit scanner. Replaces the v0 stub test
## (tests/test_audit_ffi_stub.nim, removed in the same change).
##
## Strategy: compile src/tripwire/audit_ffi.nim through `nim c
## --compileOnly` in a child process with `-d:tripwireAuditFFI` and
## TRIPWIRE_FFI_SCAN_PATHS pointed at a fixture directory whose exact
## FFI-pragma count is known by construction. Assert the scanner's
## report contains the expected header, the expected per-file counts,
## and the expected grand total.
##
## `nim c --compileOnly` is used rather than `nim check` because the
## Nim compiler deliberately skips `staticExec` / `gorgeEx` under
## `cmdCheck` (see compiler/vmops.nim ~L282). `--compileOnly` runs the
## full VM pipeline without invoking the C backend, so staticExec
## fires and the scanner's shell command runs.
##
## The fixture at tests/fixtures/ffi_audit_sample/ contains:
##   a.nim       -> 2 FFI pragmas (importc + importcpp)
##   b.nim       -> 2 FFI pragmas (importobjc + importjs)
##   c_clean.nim -> 0 FFI pragmas (but mentions "importc" in a string)
## Total: 4 FFI pragmas across 3 files.
##
## TRM-escape note: once G1's `auto.nim` umbrella is active (the
## nimble test task injects --import:tripwire/auto), the osproc
## plugin's `execCmdExTRM` is lexically in scope. Each `execCmdEx`
## call below is wrapped in `{.noRewrite.}:` at its direct call-site,
## matching the pattern in test_cap_counter.nim and test_defenses.nim.
## Wrapping execCmdEx inside a helper proc does NOT propagate the
## noRewrite effect to the proc body in the same way — the TRM still
## fires at the proc's compilation.
import std/[unittest, osproc, strutils, os]

const RepoRoot = currentSourcePath().parentDir().parentDir()
const FixtureDir = RepoRoot / "tests" / "fixtures" / "ffi_audit_sample"
const SrcPath = RepoRoot / "src"
const AuditTarget = RepoRoot / "src" / "tripwire" / "audit_ffi.nim"

template auditCmd(scanPaths: string): string =
  ## Build the nim invocation line for the audit scan. Template rather
  ## than proc so every expansion is textually present at the caller
  ## site (no cross-proc TRM leakage concerns).
  "env TRIPWIRE_FFI_SCAN_PATHS=" & quoteShell(scanPaths) &
    " nim c --compileOnly --hints:on --path:" & quoteShell(SrcPath) &
    " -d:tripwireAuditFFI " & quoteShell(AuditTarget) & " 2>&1"

suite "audit_ffi real scan (Defense 2 Part 3)":
  test "emits audit header and exact grand total for fixture dir":
    let cmd = auditCmd(FixtureDir)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0: echo output
    check code == 0
    # Header is stable text emitted once per compile when the audit
    # runs. A grep-stable marker so users can pipe the build log
    # through `grep "tripwire FFI audit"`.
    check "tripwire FFI audit" in output
    # Grand total. The fixture contains exactly 4 FFI pragmas
    # (a.nim: importc + importcpp, b.nim: importobjc + importjs,
    # c_clean.nim: 0). If this number changes, the fixture has
    # drifted or the regex has broken. Case-insensitive match because
    # "Grand total" appears in the scanner's human-readable block.
    check "grand total: 4" in output.toLowerAscii

  test "per-file counts and direct/transitive split match fixture ground truth":
    let cmd = auditCmd(FixtureDir)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0: echo output
    check code == 0
    # a.nim contributes 2, b.nim contributes 2. Direct total 4.
    check "a.nim: 2" in output
    check "b.nim: 2" in output
    check "Direct total: 4" in output
    # c_clean.nim is either listed with 0 or omitted — both acceptable.
    # What must NOT happen is an inflated count caused by its string
    # literal `"... mentions importc ..."`.
    if "c_clean.nim" in output:
      check "c_clean.nim: 0" in output
    # TRIPWIRE_FFI_SCAN_PATHS contains only the fixture dir, so all 4
    # hits count as "direct". Transitive section must report "not
    # scanned" because TRIPWIRE_FFI_TRANSITIVE_PATHS is unset.
    check "Direct FFI" in output
    check "Transitive FFI: 0 (not scanned" in output

  test "string-literal 'importc' in c_clean.nim is NOT counted":
    # Regression guard: if the scanner falls back to a naive word match
    # instead of pragma-syntax match, c_clean.nim would contribute 1
    # (from its string literal) and the grand total would be 5.
    let cmd = auditCmd(FixtureDir)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0: echo output
    check code == 0
    check "grand total: 5" notin output.toLowerAscii
    check "grand total: 4" in output.toLowerAscii

  test "module is a no-op WITHOUT -d:tripwireAuditFFI":
    # Regression guard: without the define, the module body is inert.
    # No audit header, clean compile. `nim check` is sufficient here
    # because with the define off the `when defined(...)` block is
    # skipped entirely — no staticExec to evaluate.
    let cmd = "nim check --hints:on --path:" & quoteShell(SrcPath) &
      " " & quoteShell(AuditTarget) & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0: echo output
    check code == 0
    check "tripwire FFI audit" notin output
