## tests/test_audit_ffi.nim -- WI1 v0.2 integration regression guard.
##
## v0.2 replaces v0.1's env-var contract with compiler-driven
## auto-discovery via `querySetting(SingleValueSetting.projectPath)`
## and the opt-in `-d:tripwireAuditFFITransitive` define. This file
## is the umbrella integration regression guard for that migration
## (design §5.6 breaking change).
##
## The fine-grained auto-discovery contracts live in `tests/audit_ffi/`:
##   - test_auto_projectpath.nim       -> §5.2 projectPath happy path + F3 shape
##   - test_auto_transitive_optin.nim  -> §5.3 transitive aggregate + escape hatch
##   - test_nimble_parser_limits.nim   -> §5.3 parseNimbleRequires limits
##   - test_stdlib_not_scanned.nim     -> §5.5 stdlib-never-scanned
##
## This file does NOT duplicate those checks. It pins:
##   1. Activation contract           -- the define flips the hint on.
##   2. No-op default                 -- absence of the define is silent.
##   3. Env-var independence guard    -- compile succeeds AND shape holds
##                                       even when the v0.1 env-var
##                                       names are explicitly unset,
##                                       proving v0.2 has no env-var
##                                       fallback (design §5.6).
##   4. End-to-end pragma count       -- a fixture with real FFI pragmas
##                                       surfaces in the emitted report's
##                                       per-file lines and Grand total,
##                                       closing the integration loop
##                                       from CLI -> hint body.
##
## `nim c --compileOnly` is used rather than `nim check` because the Nim
## compiler deliberately skips `staticExec` / `gorgeEx` under `cmdCheck`
## (compiler/vmops.nim ~L282). `--compileOnly` runs the full VM pipeline
## without invoking the C backend, so staticExec fires and the scanner's
## shell command runs.
##
## Nimcache caveat: each compile command uses a unique `--nimcache` dir.
## Without this, the Nim compiler serves subsequent compiles of the same
## target from cache and the `{.hint: ffiReport.}` block does NOT re-
## emit (hints fire only on fresh compiles). Cases 1 and 3 compile the
## same target (`audit_ffi.nim`) with the same defines, so any shared
## nimcache silently suppresses Case 3's assertions. See issue notes in
## compiler/condsyms + compiler/modulegraphs -- there's no public flag
## to force hint re-emission other than invalidating the cache entry.
##
## TRM-escape note: once G1's `auto.nim` umbrella is active (the nimble
## test task injects --import:tripwire/auto), the osproc plugin's
## `execCmdExTRM` is lexically in scope. Each `execCmdEx` call below is
## wrapped in `{.noRewrite.}:` at its direct call-site, matching the
## pattern in test_cap_counter.nim and test_defenses.nim. Wrapping
## execCmdEx inside a helper proc does NOT propagate the noRewrite
## effect to the proc body in the same way -- the TRM still fires at
## the proc's compilation.
import std/[unittest, osproc, strutils, os, random, times]

const RepoRoot = currentSourcePath().parentDir().parentDir()
const SrcPath = RepoRoot / "src"
const AuditTarget = RepoRoot / "src" / "tripwire" / "audit_ffi.nim"
const FixtureFFIDir = RepoRoot / "tests" / "fixtures" / "ffi_audit_sample"
  ## The fixture dir contains three `.nim` files with a known FFI
  ## pragma count: a.nim (2), b.nim (2), c_clean.nim (0). Case 4 writes
  ## a tiny driver into this dir so `querySetting(projectPath)` resolves
  ## to it and the scanner walks all four files.

randomize()

proc uniqueNimcache(tag: string): string =
  ## Per-test nimcache dir keyed by a tag + unix time + random int.
  ## Each test's compile uses a fresh cache so hint emission fires on
  ## every invocation regardless of other tests' compile history.
  getTempDir() / ("tripwire_audit_ffi_" & tag & "_" &
                  $getTime().toUnix() & "_" & $rand(high(int)))

proc uniqueDriverName(prefix: string): string =
  ## Randomized `.nim` filename for Case 4's in-fixture driver. The
  ## driver is written into FixtureFFIDir so `querySetting(projectPath)`
  ## resolves to that dir and the scanner walks a.nim + b.nim + c_clean
  ## + the driver. Random name avoids collisions with concurrent test
  ## runs and with leftover driver files from crashed prior runs.
  prefix & "_" & $getTime().toUnix() & "_" & $rand(high(int)) & ".nim"

# Pre-run sweep: remove any `driver_e2e_*.nim` from crashed prior runs.
# Case 4 writes a randomized driver into FixtureFFIDir and brackets
# its cleanup with try/finally, but a SIGKILL or compile-interrupt
# between writeFile and the finally block leaves the file behind.
# Stale drivers add noise to subsequent scans (the scanner walks them
# and folds their hit counts into the Grand total). This sweep runs
# once per test-module compile to keep the fixture dir clean.
for path in walkFiles(FixtureFFIDir / "driver_e2e_*.nim"):
  removeFile(path)

suite "audit_ffi v0.2 integration regression guard":

  test "activation: -d:tripwireAuditFFI fires the hint with Direct FFI and Grand total":
    ## Case 1. Compile `audit_ffi.nim` itself with the direct define.
    ## The module's `{.hint: ffiReport.}` MUST fire and produce a body
    ## containing:
    ##   - the stable "Direct FFI" header fragment (the v0.1-compatible
    ##     marker that downstream consumers grep for), and
    ##   - a `Grand total: N` footer (the arithmetic footer that closes
    ##     every emission). Both MUST appear on a successful compile.
    ##
    ## A regression that skips the hint or truncates the report body
    ## fails here -- this is the single load-bearing smoke test that
    ## v0.2's activation path is wired end-to-end.
    let nc = uniqueNimcache("activation")
    let cmd = "nim c --compileOnly --hints:on --nimcache:" & quoteShell(nc) &
      " --path:" & quoteShell(SrcPath) &
      " -d:tripwireAuditFFI " & quoteShell(AuditTarget) & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    try:
      if code != 0: echo output
      check code == 0
      # Stable v0.1-compatible header fragment.
      check "tripwire FFI audit (Defense 2 Part 3)" in output
      # Direct section header. The `querySetting(projectPath)` path
      # expansion is audit_ffi/test_auto_projectpath.nim's concern;
      # here we only assert the section header label fires.
      check "Direct FFI" in output
      # Grand-total footer present with a parseable integer value.
      # Weak invariant (any parseable int); the pragma-count case
      # below pins an exact floor (4) using a structurally different
      # fixture compile.
      var haveGrandTotal = false
      for ln in output.splitLines:
        let s = ln.strip()
        if s.startsWith("Grand total:"):
          let rest = s["Grand total:".len .. ^1].strip()
          try:
            discard parseInt(rest)
            haveGrandTotal = true
          except ValueError:
            discard
          break
      check haveGrandTotal
    finally:
      if dirExists(nc): removeDir(nc)

  test "no-op default: no hint emitted WITHOUT -d:tripwireAuditFFI":
    ## Case 2. Compile `audit_ffi.nim` WITHOUT the define. The entire
    ## audit body is gated under `when defined(tripwireAuditFFI):`, so
    ## no hint fires and the compile stdout contains none of the audit
    ## report's marker text.
    ##
    ## `nim check` is sufficient here because with the define off the
    ## `when defined(...)` block is skipped entirely -- no staticExec
    ## to evaluate. Matches the v0.1 no-op case's invariant (the one
    ## v0.1 case that IS preservable in v0.2 per the WI1 baseline note).
    ## `nim check` does not populate a nimcache, so no per-test cache
    ## management is needed here.
    let cmd = "nim check --hints:on --path:" & quoteShell(SrcPath) &
      " " & quoteShell(AuditTarget) & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0: echo output
    check code == 0
    # No audit header.
    check "tripwire FFI audit (Defense 2 Part 3)" notin output
    # No Direct FFI section.
    check "Direct FFI" notin output
    # No Grand total footer.
    check "Grand total:" notin output

  test "env-var independence: compile succeeds with v0.1 env-vars explicitly unset":
    ## Case 3. Regression guard for the v0.2 migration's load-bearing
    ## promise: the scanner has NO env-var fallback (design §5.6). If
    ## a future change re-introduces a `staticExec("printenv ...")`
    ## code path, it would silently work when env vars are set and
    ## silently fail (or behave inconsistently) when they are not.
    ##
    ## We prepend an `env -u ...` clause (see command below) to the
    ## compile so any inherited value from the parent shell is cleared
    ## before `nim c` runs. The compile MUST still succeed AND the
    ## emission shape (Direct FFI header + Grand total footer) MUST
    ## still hold. Any divergence from Case 1's shape proves a
    ## regression into env-var dependence.
    ##
    ## Paired with a grep for the removed env-var names under `src/`
    ## returning empty (the WI1 acceptance criterion), this forms a
    ## two-layer guard: static grep pins the source-level absence,
    ## runtime env-clearing pins the behavioral absence.
    let nc = uniqueNimcache("env_indep")
    let cmd = "env -u TRIPWIRE_FFI_SCAN_PATHS -u TRIPWIRE_FFI_TRANSITIVE_PATHS " &
      "nim c --compileOnly --hints:on --nimcache:" & quoteShell(nc) &
      " --path:" & quoteShell(SrcPath) &
      " -d:tripwireAuditFFI " & quoteShell(AuditTarget) & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    try:
      if code != 0: echo output
      check code == 0
      # Same shape contract as Case 1 MUST hold. A regression that
      # only emits the header when env vars are set would fail one of
      # these three checks.
      check "tripwire FFI audit (Defense 2 Part 3)" in output
      check "Direct FFI" in output
      var haveGrandTotal = false
      for ln in output.splitLines:
        let s = ln.strip()
        if s.startsWith("Grand total:"):
          let rest = s["Grand total:".len .. ^1].strip()
          try:
            discard parseInt(rest)
            haveGrandTotal = true
          except ValueError:
            discard
          break
      check haveGrandTotal
    finally:
      if dirExists(nc): removeDir(nc)

  test "end-to-end pragma count: fixture with 4 .importc-family pragmas surfaces in Grand total":
    ## Case 4. Integration loop: write a tiny driver into the fixture
    ## dir, compile the driver with `-d:tripwireAuditFFI`. The driver
    ## imports `tripwire/audit_ffi` to pull the audit module into the
    ## compile graph so its `{.hint.}` fires.
    ## `querySetting(projectPath)` resolves to the fixture dir; the
    ## scanner walks every `.nim` file in it:
    ##   - a.nim:       importc + importcpp     = 2 hits
    ##   - b.nim:       importobjc + importjs   = 2 hits
    ##   - c_clean.nim: 0 (its string literal mentioning "importc" is
    ##                     rejected by the pragma-syntax regex)
    ##   - driver:      0 (only an import)
    ## Ground-truth total: 4.
    ##
    ## Per-file assertions pin the pragma-syntax regex's correctness:
    ## a regression that falls back to bare word matching would inflate
    ## c_clean.nim's count; a regression that drops one of the four
    ## pragma keywords (importc / importcpp / importobjc / importjs)
    ## would deflate either a.nim or b.nim to 1. The Grand total
    ## arithmetic pins the summation pipeline (scanDir -> parseReport
    ## -> hint body assembly) end-to-end.
    ##
    ## The fixture lacks a `.nimble`, so absent the transitive define
    ## the placeholder section is emitted and the grand total equals
    ## the direct total.
    let driverPath = FixtureFFIDir / uniqueDriverName("driver_e2e")
    writeFile(driverPath, "import tripwire/audit_ffi\n")
    let nc = uniqueNimcache("e2e_count")
    let cmd = "nim c --compileOnly --hints:on --nimcache:" & quoteShell(nc) &
      " --path:" & quoteShell(SrcPath) &
      " -d:tripwireAuditFFI " & quoteShell(driverPath) & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    try:
      if code != 0: echo output
      check code == 0
      # Stable audit header.
      check "tripwire FFI audit (Defense 2 Part 3)" in output
      # Per-file ground-truth lines (see docstring for pragma origins).
      check "a.nim: 2" in output
      check "b.nim: 2" in output
      # Grand total is 4 (direct 4 + transitive 0, since transitive
      # define is absent). Integer-parse comparison rather than
      # substring match so a future emission that pads the integer
      # (e.g. "Grand total: 04") or adds a trailing word still works.
      var grandTotal = -1
      for ln in output.splitLines:
        let s = ln.strip()
        if s.startsWith("Grand total:"):
          let rest = s["Grand total:".len .. ^1].strip()
          try:
            grandTotal = parseInt(rest)
          except ValueError:
            grandTotal = -1
          break
      check grandTotal == 4
    finally:
      if fileExists(driverPath): removeFile(driverPath)
      if dirExists(nc): removeDir(nc)
