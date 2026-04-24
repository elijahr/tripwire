## tests/audit_ffi/test_auto_transitive_optin.nim — WI1 Task 1.4 acceptance.
##
## Asserts the `-d:tripwireAuditFFITransitive` opt-in contract introduced
## by Task 1.4 (design §5.3 output example lines 1024-1040 and §5.4):
##
##   Case A: `-d:tripwireAuditFFI` ONLY (no transitive define) keeps
##           the Task 1.2 placeholder in place. The report MUST NOT
##           advertise any per-package aggregate section.
##
##   Case B: `-d:tripwireAuditFFI -d:tripwireAuditFFITransitive`
##           activates real per-package aggregation. The emission
##           includes a `Transitive FFI (per-package aggregate` header,
##           per-package lines (`  <pkgName>: <count>`), a
##           `Transitive total:` line, and a `Grand total:` line whose
##           integer equals direct + transitive. The placeholder MUST
##           be absent.
##
##   Case C: Missing `.nimble` (driver sits in a tmp dir with no
##           `.nimble`). Task 1.4 spec: the `scanTransitive` path
##           emits a `{.warning.}` about the missing file and proceeds
##           with direct scope only. The compile MUST still succeed
##           (warning, not error). The transitive section is present
##           but empty (no per-package lines; transitive total = 0).
##
##   Case D: `-d:tripwireAuditFFIExtraRequires:"parsetoml"` escape
##           hatch. Drives from a tmp dir whose `.nimble` has NO
##           `requires` lines, but the define supplies `parsetoml`.
##           The per-package aggregate MUST list `parsetoml:` — proves
##           the escape hatch threaded through `mergeExtraRequires`
##           into the transitive scan.
##           `parsetoml` is chosen because:
##             1. It is the only transitive require of tripwire itself,
##                so the test-runner provisions guarantee it exists
##                (the tripwire test matrix would have already failed
##                at nimble install time if it did not).
##             2. Its installed tree contains zero FFI pragmas
##                (verified empirically on parsetoml 0.7.2), so the
##                aggregate line is deterministic (`parsetoml: 0`).
##
## Trade-off on Case B's driver location: rather than copy or link a
## `.nimble` into a tmp dir, the driver is written to the tripwire
## repo root so `querySetting(projectPath)` resolves to that root,
## and `findFirstNimble(projectPath)` picks up `tripwire.nimble`
## directly. This avoids duplicating a stub `.nimble` file and
## coincidentally guarantees we exercise a REAL `.nimble` parse
## pipeline (not a synthetic fixture). Cost: the tmp driver file has
## to be cleaned up from the repo root on test exit; we bracket each
## write with `try/finally + removeFile`. The driver filename is
## randomized so concurrent runs don't collide.
##
## Strategy mirrors `test_auto_projectpath.nim`: `nim c --compileOnly`
## in a child process, capture stderr, inspect for the expected
## header/footer lines. `--compileOnly` is load-bearing because
## `staticExec` does not run under `nim check`.

import std/[unittest, osproc, strutils, os, random, times]

const RepoRoot = currentSourcePath().parentDir().parentDir().parentDir()
const SrcPath = RepoRoot / "src"
const AuditTarget = RepoRoot / "src" / "tripwire" / "audit_ffi.nim"

# `randomize()` needed for `rand()` in writeDriver helpers.
randomize()

proc uniqueDriverPath(dir: string, prefix: string): string =
  ## Build a randomized driver path under `dir`. Each test writes its
  ## own driver so failures do not cross-contaminate and concurrent
  ## runs do not collide.
  dir / (prefix & "_" & $getTime().toUnix() & "_" & $rand(high(int))) & ".nim"

proc runNim(defines: seq[string], target: string): tuple[output: string, code: int] =
  ## Drive `nim c --compileOnly --hints:on` against `target` with the
  ## supplied define flags. `--hints:on` is required so the audit's
  ## `{.hint.}` emission appears in captured output.
  var defs = ""
  for d in defines:
    defs.add " -d:" & d
  let cmd = "nim c --compileOnly --hints:on --path:" & quoteShell(SrcPath) &
    defs & " " & quoteShell(target) & " 2>&1"
  var output: string
  var code: int
  {.noRewrite.}:
    (output, code) = execCmdEx(cmd)
  (output, code)

proc extractIntAfter(output: string, prefix: string): int =
  ## Pull the integer following `prefix` on the first matching stripped
  ## line. Returns -1 if not found so callers can assert failure
  ## explicitly. Line-by-line search preserves robustness against
  ## surrounding compiler noise (hint preambles, `SuccessX` footer).
  for ln in output.splitLines:
    let s = ln.strip()
    if s.startsWith(prefix):
      let rest = s[prefix.len .. ^1].strip()
      try:
        return parseInt(rest)
      except ValueError:
        return -1
  -1

suite "audit_ffi transitive opt-in (Task 1.4)":

  test "default -d:tripwireAuditFFI keeps Task-1.2 placeholder; no per-package section":
    # Case A: compile `audit_ffi.nim` itself with ONLY the direct
    # define. projectPath resolves to `src/tripwire`, which has no
    # `.nimble`. The transitive block is compiled OUT at the
    # `when defined(tripwireAuditFFITransitive):` gate, so the
    # placeholder must appear verbatim.
    let (output, code) = runNim(@["tripwireAuditFFI"], AuditTarget)
    if code != 0: echo output
    check code == 0
    # Task-1.2 placeholder must be present.
    check "Transitive FFI: 0 (not scanned" in output
    check "-d:tripwireAuditFFITransitive" in output
    # The Task-1.4 aggregate header MUST NOT appear.
    check "Transitive FFI (per-package aggregate" notin output
    # No per-package lines advertised when transitive is off.
    check "Transitive total:" notin output

  test "both defines: report includes per-package aggregates and grand-total arithmetic":
    # Case B: compile a driver placed at the tripwire repo root so
    # `querySetting(projectPath)` resolves to RepoRoot and
    # `findFirstNimble` picks up tripwire.nimble. tripwire.nimble's
    # only non-`nim` requires is `parsetoml` which has 0 FFI pragmas
    # in its installed tree (parsetoml 0.7.2 verified empirically),
    # making the transitive total deterministic (0).
    let driverPath = uniqueDriverPath(RepoRoot, "audit_transitive_driver")
    writeFile(driverPath, "import tripwire/audit_ffi\n")
    try:
      let (output, code) = runNim(
        @["tripwireAuditFFI", "tripwireAuditFFITransitive"], driverPath)
      if code != 0: echo output
      check code == 0
      # Task-1.4 aggregate header present (Task-1.2 placeholder absent).
      check "Transitive FFI (per-package aggregate" in output
      check "Transitive FFI: 0 (not scanned" notin output
      # Per-package line for parsetoml present.
      # Presence-check only; parsetoml's FFI count could change upstream
      # without invalidating the aggregate-emission contract this test
      # asserts. Arithmetic invariant below pins the emission shape.
      check "  parsetoml:" in output
      # Both totals emitted.
      let directTotal = extractIntAfter(output, "Direct total:")
      let transitiveTotal = extractIntAfter(output, "Transitive total:")
      let grandTotal = extractIntAfter(output, "Grand total:")
      check directTotal >= 0
      check transitiveTotal >= 0
      check grandTotal >= 0
      # Arithmetic invariant: grand total equals direct + transitive.
      # The design's "per-package aggregate" output shape pins this
      # equation; a regression that double-counts or drops direct
      # hits fails here regardless of the specific integers.
      check grandTotal == directTotal + transitiveTotal
      # Sanity-only: transitiveTotal must be non-negative. Previously
      # pinned to 0, but parsetoml gaining FFI pragmas upstream would
      # fail this for the wrong reason. The grand = direct + transitive
      # invariant above pins the arithmetic shape regardless.
      check transitiveTotal >= 0
    finally:
      removeFile(driverPath)

  test "missing .nimble emits warning and falls back to direct-only scope":
    # Case C: tmp dir with a driver but no `.nimble`. projectPath
    # resolves to the tmp dir; findFirstNimble returns ""; the
    # scanTransitive branch emits a `{.warning.}` and returns
    # empty aggregates. The compile MUST succeed (warning, not error).
    let tmpDir = getTempDir() / ("tripwire_ffi_no_nimble_" &
                                 $getTime().toUnix() & "_" &
                                 $rand(high(int)))
    createDir(tmpDir)
    let driverPath = uniqueDriverPath(tmpDir, "driver")
    writeFile(driverPath, "import tripwire/audit_ffi\n")
    try:
      let (output, code) = runNim(
        @["tripwireAuditFFI", "tripwireAuditFFITransitive"], driverPath)
      if code != 0: echo output
      check code == 0
      # Warning MUST fire: mentions the missing-nimble condition and
      # the projectPath it searched. We pin substrings rather than
      # exact text because the Nim compiler prefixes warnings with
      # its own `(line, col)` location marker.
      check "tripwire FFI transitive: no .nimble found" in output
      check tmpDir in output
      # Aggregate header still prints (transitive branch is active;
      # it simply has nothing to show). No per-package lines.
      check "Transitive FFI (per-package aggregate" in output
      check "  parsetoml" notin output
      # Transitive total must be 0 under this fallback.
      let transitiveTotal = extractIntAfter(output, "Transitive total:")
      check transitiveTotal == 0
    finally:
      removeFile(driverPath)
      removeDir(tmpDir)

  test "escape hatch: -d:tripwireAuditFFIExtraRequires injects pkg into aggregate":
    # Case D: tmp dir with a minimal `.nimble` that has NO `requires`
    # lines. The extras define supplies `parsetoml`. The per-package
    # aggregate MUST include `parsetoml:` — proves the escape hatch
    # threaded through `mergeExtraRequires` into the transitive scan
    # even though the `.nimble` had no auto-detected requires.
    let tmpDir = getTempDir() / ("tripwire_ffi_extras_" &
                                 $getTime().toUnix() & "_" &
                                 $rand(high(int)))
    createDir(tmpDir)
    writeFile(tmpDir / "stub.nimble", "# minimal stub, no requires\n")
    let driverPath = uniqueDriverPath(tmpDir, "driver")
    writeFile(driverPath, "import tripwire/audit_ffi\n")
    try:
      let (output, code) = runNim(
        @["tripwireAuditFFI",
          "tripwireAuditFFITransitive",
          "tripwireAuditFFIExtraRequires:parsetoml"],
        driverPath)
      if code != 0: echo output
      check code == 0
      # parsetoml appears in the aggregate despite stub.nimble having
      # zero requires. This is the escape hatch proof.
      # Presence-check: proves the escape hatch threaded the pkg into the aggregate,
      # without coupling to parsetoml's upstream FFI count (which could change).
      check "  parsetoml:" in output
      # Aggregate header present.
      check "Transitive FFI (per-package aggregate" in output
      # No warning about a missing `.nimble` -- stub.nimble was
      # located successfully.
      check "tripwire FFI transitive: no .nimble found" notin output
    finally:
      removeFile(driverPath)
      removeFile(tmpDir / "stub.nimble")
      removeDir(tmpDir)
