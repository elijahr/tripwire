## tests/audit_ffi/test_stdlib_not_scanned.nim -- WI1 Task 1.5 acceptance.
##
## Negative regression guard for design §5.5 ("Stdlib explicitly
## excluded -- never scanned"). The v0.2 scanner is scoped: direct
## scope walks `querySetting(projectPath)` only, transitive scope
## parses the project's `.nimble` requires and walks each direct
## dep's installed dir. A regression that replaces either scoped walk
## with a naive `querySettingSeq(searchPaths)` iteration would silently
## drag the entire Nim stdlib (posix, winlean, httpclient+openssl,
## dynlib, times, os, ...) into the report. On a typical dev install
## that's ~4,400 files / ~8,200 FFI hits -- noise, not signal (design
## §5.4, lines 1044-1048). The negative assertions below pin the
## contract: stdlib filenames MUST NOT appear in the emitted hint.
##
## Test strategy: drive a compile of a tiny driver module with both
## `-d:tripwireAuditFFI` and `-d:tripwireAuditFFITransitive`, inspect
## the `{.hint: ffiReport.}` body for the ABSENCE of stdlib filenames
## and paths. Because the whole audit runs at compile time via
## `staticExec`, `--compileOnly` suffices; we never need to link or
## execute the built binary.
##
## The transitive-layer edge case (`requires "nim"` skip, design §5.5
## lines 913-931 cross-reference) is covered in two forms:
##   1. `.nimble` fixture with `requires "nim >= 2.0"` -- the parser
##      strips it. Re-asserts Task 1.3's fixture-driven coverage here
##      alongside the stdlib negative so the two §5.5 invariants live
##      in one place.
##   2. Escape-hatch belt-and-braces: `-d:tripwireAuditFFIExtraRequires:"nim"`
##      explicitly asks the scanner to scan nim's stdlib. The skip
##      logic MUST re-apply on the escape-hatch path (defense in
##      depth: a user misreading the docs and adding `nim` to the CSV
##      must not trigger a stdlib walk).

import std/[unittest, osproc, strutils, os, random, times]

const RepoRoot = currentSourcePath().parentDir().parentDir().parentDir()
const SrcPath = RepoRoot / "src"
const FixtureDir = RepoRoot / "tests" / "fixtures" / "nimble_parser"

# Stdlib filenames that MUST NOT appear in the emitted hint. These
# are the most common FFI-heavy stdlib modules; if any appears, the
# scanner regressed into a `searchPaths` walk. List is non-exhaustive
# on purpose: adding more only tightens the guard, never loosens it.
# Note: `os.nim` is a common filename that a USER project might also
# ship (e.g. a file literally named `os.nim`). We include it here
# because the Task 1.5 fixture driver lives in a tmp dir and cannot
# legitimately produce a file named `os.nim`; any match MUST originate
# from the stdlib tree. See the per-test comments for the origin
# reasoning per filename.
const StdlibFilenames = [
  "posix.nim",        # std/posix -- heavy importc surface
  "winlean.nim",      # std/winlean -- Windows FFI
  "httpclient.nim",   # std/httpclient -- openssl dynlib bindings
  "openssl.nim",      # std/openssl -- ssl FFI
  "dynlib.nim",       # std/dynlib -- dlopen family
  "times.nim",        # std/times -- localtime/gmtime importc
  "os.nim",           # std/os -- pulls posix/winlean transitively
]

# Stdlib PATH fragments that MUST NOT appear in the `Direct FFI (paths: ...)`
# header. Covers the mise-managed Nim install (this dev's layout) and
# the common Linux `/usr/lib/nim` layout. Sub-path fragments matter
# more than the absolute root; a regression that walked `searchPaths`
# would yield paths with `/lib/pure/`, `/lib/std/`, or a Nim version
# dir in them.
const StdlibPathFragments = [
  "/lib/pure/",
  "/lib/std/",
  "/lib/posix",
  "/lib/windows",
  "/nim/2.2.6/lib",  # mise layout for this dev; if the path appears here
                     # it means the scanner walked the stdlib root.
]

# `randomize()` needed for `rand()` in tmp-path generation.
randomize()

proc uniqueTmpDir(prefix: string): string =
  ## Build a randomized tmp directory path. Each test gets its own
  ## sandbox so concurrent runs and crashed prior runs do not
  ## cross-contaminate.
  let p = getTempDir() / (prefix & "_" & $getTime().toUnix() & "_" & $rand(high(int)))
  createDir(p)
  p

template runNim(defines: seq[string], target: string): tuple[output: string, code: int] =
  ## Drive `nim c --compileOnly --hints:on` against `target` with the
  ## supplied define flags. `--hints:on` is required so the audit's
  ## `{.hint.}` emission lands in captured output.
  ##
  ## Template (not proc) so its body inlines at each callsite. Callers
  ## MUST wrap the template invocation in `{.noRewrite.}:` so the
  ## inlined `execCmdEx(cmd)` call falls under the caller's noRewrite
  ## scope and the osproc plugin's `execCmdExTRM` is suppressed.
  ## Defense 3's 15-rewrite cap (cap_counter.nim) would otherwise trip
  ## in the aggregate `tests/all_tests.nim` compile.
  var defs = ""
  for d in defines:
    defs.add " -d:" & d
  let cmd = "nim c --compileOnly --hints:on --path:" & quoteShell(SrcPath) &
    defs & " " & quoteShell(target) & " 2>&1"
  var output: string
  var code: int
  (output, code) = execCmdEx(cmd)
  (output, code)

template compileDriverWithTestHook(driverPath: string,
                                   extraDefines: seq[string] = @[]): tuple[output: string, code: int] =
  ## Compile a driver that reaches into the internal CT helpers via
  ## `-d:tripwireAuditFFITestHook`. Used only by the `requires "nim"`
  ## parser/merge tests where the driver calls `parseNimbleRequires`
  ## or `mergeExtraRequires` directly and asserts at CT via `doAssert`.
  ##
  ## Template (see `runNim` above for the full rationale): callers MUST
  ## wrap template invocations in `{.noRewrite.}:` to suppress the
  ## osproc TRM and keep the aggregate test's TRM-rewrite count under
  ## Defense 3's 15-rewrite cap.
  var defs = " -d:tripwireAuditFFI -d:tripwireAuditFFITransitive -d:tripwireAuditFFITestHook"
  for d in extraDefines:
    defs.add " -d:" & d
  let cmd = "nim c --compileOnly --hints:off --path:" & quoteShell(SrcPath) &
    defs & " " & quoteShell(driverPath) & " 2>&1"
  var output: string
  var code: int
  (output, code) = execCmdEx(cmd)
  (output, code)

proc extractAuditReport(output: string): string =
  ## Slice the audit hint block out of `nim c`'s full stdout. The
  ## compiler itself prints its config-file path diagnostics (e.g.
  ## `/Users/x/.../mise/installs/nim/2.2.6/config/nim.cfg`) and may
  ## print other stdlib paths in its own hints; those are not part of
  ## the FFI audit under test and would cause false-positive matches
  ## on `NimLibPath notin output` / `/nim/2.2.6/lib notin output`.
  ##
  ## The report is bounded below by the header line
  ## `tripwire FFI audit (Defense 2 Part 3)` (emitted by the hint in
  ## `audit_ffi.nim`) and above by the `Grand total: N` line (also
  ## emitted by the same hint). Returns the inclusive slice; empty
  ## string if either bound is missing.
  var startIdx = -1
  var endIdx = -1
  let lines = output.splitLines()
  for i, ln in lines:
    let s = ln.strip()
    if startIdx < 0 and "tripwire FFI audit (Defense 2 Part 3)" in s:
      startIdx = i
    elif startIdx >= 0 and s.startsWith("Grand total:"):
      endIdx = i
      break
  if startIdx < 0 or endIdx < 0:
    return ""
  result = lines[startIdx .. endIdx].join("\n")

proc tripleQuote(s: string): string =
  ## Build a Nim triple-quoted string literal that embeds `s` verbatim.
  ## Mirrors the helper in `test_nimble_parser_limits.nim`: Nim's
  ## `"""..."""` strips the leading newline after the opening delimiter,
  ## so we prepend one explicit newline to preserve `s`'s first line.
  ## Fixtures never contain `"""` so no escaping is needed.
  "\"\"\"\n" & s & "\n\"\"\""

suite "audit_ffi stdlib-never-scanned guard (Task 1.5)":

  test "stdlib filenames not cited in FFI report (both defines active)":
    # Compile a driver in a sandboxed tmp dir with both defines. The
    # tmp dir has no `.nimble`, so the transitive scan fires its
    # missing-nimble warning and empties the transitive aggregate.
    # The direct scan walks the tmp dir -- which contains only our
    # driver -- so NO stdlib filename can legitimately appear in the
    # hint output. Any match proves a regression.
    #
    # We scope the stdlib-absence checks to the audit report region
    # (between the `tripwire FFI audit (Defense 2 Part 3)` header and
    # the `Grand total:` line) because `nim c`'s own stdout contains
    # unrelated config-file paths that happen to mention the stdlib.
    # See `extractAuditReport` for rationale.
    let tmpDir = uniqueTmpDir("tripwire_stdlib_guard")
    let driverPath = tmpDir / "driver.nim"
    writeFile(driverPath, "import tripwire/audit_ffi\n")
    try:
      var output: string
      var code: int
      {.noRewrite.}:
        (output, code) = runNim(
          @["tripwireAuditFFI", "tripwireAuditFFITransitive"], driverPath)
      if code != 0: echo output
      check code == 0
      # Bracket the assertion set with a sanity check that the audit
      # hint actually fired; otherwise the negative checks pass
      # vacuously.
      check "tripwire FFI audit (Defense 2 Part 3)" in output
      let report = extractAuditReport(output)
      check report.len > 0  # sanity: extraction actually found bounds
      # Per §5.5 the report must not cite any stdlib filename.
      for fn in StdlibFilenames:
        check fn notin report
    finally:
      removeFile(driverPath)
      removeDir(tmpDir)

  test "stdlib paths not cited in Direct FFI header":
    # The `Direct FFI (paths: <projectPath>)` header is the exact line
    # where a regression into `searchPaths` walking would first show:
    # the header would either contain comma-separated stdlib paths, or
    # per-file lines whose paths fall under `/lib/pure/` / `/lib/std/`.
    # We assert the tmp-dir path IS the scanned root AND no stdlib
    # fragment appears anywhere in the output.
    #
    # Primary guard (dynamic, version-agnostic): `NimLibPath` is the
    # value of `querySetting(SingleValueSetting.libPath)` captured at
    # CT inside the driver. ANY file under the Nim stdlib tree has a
    # path prefixed by NimLibPath, so asserting NimLibPath `notin output`
    # is strictly stronger than enumerating path fragments -- a future
    # Nim version with a new `/lib/<subdir>/` (e.g. `/lib/impure/`,
    # `/lib/wrappers/`) would regress past `StdlibPathFragments` but
    # could not regress past this dynamic check. The hand-enumerated
    # list below remains a belt-and-braces supplement.
    let tmpDir = uniqueTmpDir("tripwire_stdlib_paths")
    let driverPath = tmpDir / "driver.nim"
    # Driver: `static: echo NIM_LIB_PATH=...` so the test harness can
    # extract the Nim stdlib root from compile stdout and assert it
    # is absent from the audit report.
    writeFile(driverPath, """
import std/compilesettings
import tripwire/audit_ffi
static:
  const p = querySetting(SingleValueSetting.libPath)
  doAssert p.len > 0, "nim libPath should always be set at CT"
  echo "NIM_LIB_PATH=" & p
""")
    try:
      var output: string
      var code: int
      {.noRewrite.}:
        (output, code) = runNim(
          @["tripwireAuditFFI", "tripwireAuditFFITransitive"], driverPath)
      if code != 0: echo output
      check code == 0
      # Extract NimLibPath from the driver's CT echo.
      var nimLibPath = ""
      for ln in output.splitLines:
        let s = ln.strip()
        if s.startsWith("NIM_LIB_PATH="):
          nimLibPath = s["NIM_LIB_PATH=".len .. ^1]
          break
      check nimLibPath.len > 0  # sanity: the CT echo fired
      # Scope stdlib-absence checks to the audit report region, not
      # the full compile stdout (which contains nim c's own config
      # diagnostics that reference the stdlib path).
      let report = extractAuditReport(output)
      check report.len > 0
      # Pull the `Direct FFI (paths: ...)` line so we can pin its
      # contents independently of any other line in the hint.
      var directLine = ""
      for ln in report.splitLines:
        let s = ln.strip()
        if s.startsWith("Direct FFI (paths:"):
          directLine = s
          break
      check directLine.len > 0
      # PRIMARY GUARD (dynamic): no stdlib path anywhere in the report.
      # This is stronger than the fragment enumeration below because it
      # covers every subdir of libPath without needing a hand-maintained
      # list. See the header comment for rationale.
      check nimLibPath notin report
      # Positive assertion: header cites the tmp dir (projectPath).
      # On macOS, `getTempDir()` returns `/var/folders/.../T/` but the
      # actual resolved path is `/private/var/folders/.../T/`. The
      # `nim c` invocation's `projectPath` resolves to the real path.
      # Both forms appear as prefixes of the real path, so we check
      # that the scanned root is NOT a stdlib root by absence of
      # fragments rather than by exact prefix match.
      for frag in StdlibPathFragments:
        check frag notin directLine
      # Belt-and-braces: no stdlib path fragment ANYWHERE in the audit
      # report (per-file lines, transitive aggregate, etc.).
      for frag in StdlibPathFragments:
        check frag notin report
    finally:
      removeFile(driverPath)
      removeDir(tmpDir)

  test "[§5.5 cross-ref] parseNimbleRequires skips requires \"nim\" -- intentionally duplicates Task 1.3 parser coverage":
    # Reuse Task 1.3's `nim_dep.nimble` fixture: `requires "nim >= 2.0"`
    # and `requires "other"`. The parser must strip `nim` and keep
    # `other`. This re-asserts the §5.5 parser invariant from the
    # stdlib-guard vantage point -- a parser regression that let `nim`
    # through would chain into a stdlib walk via scanTransitive.
    let nimDep = readFile(FixtureDir / "nim_dep.nimble")
    let driverBody = """
import std/[os, strutils]
import tripwire/audit_ffi

const content = """ & tripleQuote(nimDep) & """

static:
  let got = parseNimbleRequires(content)
  doAssert got == @["other"], "got=" & $got
"""
    let tmpDir = uniqueTmpDir("tripwire_nim_skip")
    let driverPath = tmpDir / "driver.nim"
    writeFile(driverPath, driverBody)
    try:
      var output: string
      var code: int
      {.noRewrite.}:
        (output, code) = compileDriverWithTestHook(driverPath)
      if code != 0: echo output
      check code == 0
    finally:
      removeFile(driverPath)
      removeDir(tmpDir)

  test "escape hatch cannot force-inject `nim`: mergeExtraRequires skips it":
    # Belt-and-braces (design §5.5 defense in depth). A user who
    # misreads the docs and sets `-d:tripwireAuditFFIExtraRequires:"nim"`
    # MUST NOT be able to force the scanner into the stdlib tree. The
    # skip logic applies on BOTH the auto-detected path (parseNimbleRequires)
    # AND the escape-hatch path (mergeExtraRequires).
    #
    # This test drives mergeExtraRequires directly via the test-hook
    # export. Auto set is `@["other"]`; extras CSV is `"nim,parsetoml"`.
    # Expected result: `@["other", "parsetoml"]` -- `nim` stripped from
    # the extras CSV by the same §5.5 invariant the parser applies.
    #
    # Also assert that `mergeExtraRequires` emits a CT echo when it
    # filters `nim`. Silent drops hide user intent; the echo makes the
    # filter visible to the operator who typed `nim` into the CSV. The
    # `echo` runs at compile time (it's inside a `{.compileTime.}`
    # proc invoked from a `static:` block), so its output lands in the
    # captured compile stdout alongside our `doAssert` chatter.
    let driverBody = """
import std/[os, strutils]
import tripwire/audit_ffi

static:
  let got = mergeExtraRequires(@["other"])
  doAssert got == @["other", "parsetoml"], "got=" & $got
"""
    let tmpDir = uniqueTmpDir("tripwire_nim_escape_hatch")
    let driverPath = tmpDir / "driver.nim"
    writeFile(driverPath, driverBody)
    try:
      var output: string
      var code: int
      {.noRewrite.}:
        (output, code) = compileDriverWithTestHook(
          driverPath, @["tripwireAuditFFIExtraRequires:\"nim,parsetoml\""])
      if code != 0: echo output
      check code == 0
      # CT-echo assertion: the `nim` filter must surface to the
      # operator. The design-§5.5 phrase is the load-bearing substring
      # so future edits to the echo text retain the reference.
      check "stdlib scan forbidden by design §5.5" in output
    finally:
      removeFile(driverPath)
      removeDir(tmpDir)
