## tests/audit_ffi/test_nimble_parser_limits.nim -- WI1 Task 1.3 acceptance.
##
## Asserts the `.nimble` requires-parser contract (design §5.3 lines
## 900-1000) and its DOCUMENTED limits. The procs under test are gated
## under `when defined(tripwireAuditFFI) and defined(tripwireAuditFFITransitive):`
## in `src/tripwire/audit_ffi.nim`, so the test cannot import them
## directly from a module compiled without the defines. Strategy: write
## a small driver `.nim` snippet to a tmp file, compile it via
## `nim c --compileOnly -d:tripwireAuditFFI -d:tripwireAuditFFITransitive`,
## and rely on `static: doAssert ...` inside the driver to fail the
## compile if the parser returns the wrong value. The outer test just
## checks exit code.
##
## Compile-time doAssert is the load-bearing mechanism here: a failed
## doAssert raises at CT and the nim compile returns non-zero, which
## the outer unittest surfaces as a failed `check code == 0`. The
## driver's stderr is only consulted on failure (via `echo output`).

import std/[unittest, osproc, strutils, os, random, times]

const RepoRoot = currentSourcePath().parentDir().parentDir().parentDir()
const SrcPath = RepoRoot / "src"
const FixtureDir = RepoRoot / "tests" / "fixtures" / "nimble_parser"
  ## `audit_ffi.nim` is imported by the driver so its gated procs become
  ## visible. `--path:<SrcPath>` allows the driver's
  ## `import tripwire/audit_ffi` to resolve.

proc writeDriver(body: string): string =
  ## Write a driver `.nim` file to a unique tmp path and return it.
  ## Each test writes its own driver so failures don't cross-contaminate.
  let tmpDir = getTempDir() / "tripwire_nimble_parser_test"
  createDir(tmpDir)
  let path = tmpDir / ("driver_" & $getTime().toUnix() & "_" &
                        $rand(high(int))) & ".nim"
  writeFile(path, body)
  path

template compileDriver(driverPath: string): tuple[output: string, code: int] =
  ## Compile the driver with both transitive defines plus the test-hook
  ## define that re-exports the internal parser helpers so the driver
  ## can reach them. --compileOnly skips the C backend (we only need
  ## CT eval of the driver's asserts).
  ##
  ## Template (not proc) so its body inlines at each callsite. Callers
  ## MUST wrap the template invocation in `{.noRewrite.}:` so the
  ## inlined `execCmdEx(cmd)` call falls under the caller's noRewrite
  ## scope and the osproc plugin's `execCmdExTRM` is suppressed.
  ## Defense 3's 15-rewrite cap (cap_counter.nim) would otherwise trip
  ## in the aggregate `tests/all_tests.nim` compile.
  let cmd = "nim c --compileOnly --hints:off --path:" & quoteShell(SrcPath) &
    " -d:tripwireAuditFFI -d:tripwireAuditFFITransitive" &
    " -d:tripwireAuditFFITestHook " &
    quoteShell(driverPath) & " 2>&1"
  var output: string
  var code: int
  (output, code) = execCmdEx(cmd)
  (output, code)

# Each driver imports audit_ffi so the gated procs resolve. The import
# triggers audit_ffi's own `{.hint.}` emission which scans the tmp
# driver's own dir for FFI pragmas (zero, since the tmp driver only
# calls our parser). `--hints:off` in compileDriver silences that.
const DriverHeader = """
import std/[os, strutils]
import tripwire/audit_ffi
"""

# `randomize()` needed for `rand()` in writeDriver.
randomize()

proc tripleQuote(s: string): string =
  ## Build a Nim triple-quoted string literal that embeds `s` verbatim.
  ## Nim's `"""..."""` strips the leading newline after the opening
  ## delimiter, so we prepend one explicit newline to `s` to preserve
  ## its first line. Fixtures never contain `"""` so no escaping is
  ## needed. An explicit trailing newline before the closing delimiter
  ## makes the generated driver file readable when debugging failures.
  "\"\"\"\n" & s & "\n\"\"\""

suite "audit_ffi .nimble parser limits (Task 1.3)":

  test "parseNimbleRequires handles simple single-line requires with version bounds":
    # Happy path: `requires "foo"` and `requires "bar >= 1.0"`.
    # Version bounds stripped; output order preserved; dedup'd.
    let simple = readFile(FixtureDir / "simple.nimble")
    let driver = DriverHeader & "\nconst content = " & tripleQuote(simple) & """

static:
  let got = parseNimbleRequires(content)
  doAssert got == @["foo", "bar"], "got=" & $got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "parseNimbleRequires accepts tab-separator and zero-space forms after keyword":
    # Prefix check must tolerate `requires\t"pkg"` (tab) and
    # `requires"pkg"` (no space) alongside the canonical space form.
    # All three are syntactically valid in `.nimble` files; rejecting
    # them silently dropped real deps.
    let tabNoSpace = readFile(FixtureDir / "tab_no_space.nimble")
    let driver = DriverHeader & "\nconst content = " & tripleQuote(tabNoSpace) & """

static:
  let got = parseNimbleRequires(content)
  doAssert got == @["tab-sep", "no-space", "normal"], "got=" & $got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "parseNimbleRequires MISSES continuation lines of multi-line requires (documented limit)":
    # `multiline.nimble` has `requires "first >= 1.0",\n  "second >= 2.0",\n  "third"`.
    # Only `first` is captured. `second` and `third` are on continuation
    # lines which the line-by-line parser does not inspect.
    let multiline = readFile(FixtureDir / "multiline.nimble")
    let driver = DriverHeader & "\nconst content = " & tripleQuote(multiline) & """

static:
  let got = parseNimbleRequires(content)
  doAssert got == @["first"], "got=" & $got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "parseNimbleRequires INCLUDES requires inside when/if blocks (documented limit)":
    # Control flow is NOT evaluated; every quoted requires line is
    # picked up regardless of syntactic context.
    let conditional = readFile(FixtureDir / "conditional.nimble")
    let driver = DriverHeader & "\nconst content = " & tripleQuote(conditional) & """

static:
  let got = parseNimbleRequires(content)
  doAssert got == @["alpha", "beta", "gamma"], "got=" & $got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "parseNimbleRequires SKIPS variable-expansion requires (documented limit)":
    # `requires "chronos >= " & chronosVer` contains `&` -- parser cannot
    # resolve; line is skipped entirely, leaving the returned seq empty
    # for this fixture (the fixture has no other requires).
    let variable = readFile(FixtureDir / "variable.nimble")
    let driver = DriverHeader & "\nconst content = " & tripleQuote(variable) & """

static:
  let got = parseNimbleRequires(content)
  doAssert got == newSeq[string](), "got=" & $got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "parseNimbleRequires SKIPS requires \"nim\" lines":
    # `nim` itself must never appear in the output because scanning
    # nim's stdlib is forbidden (§5.5). Verifies both `requires "nim"`
    # and `requires "nim >= 2.0"` forms are filtered, while other deps
    # on the same file remain.
    let nimDep = readFile(FixtureDir / "nim_dep.nimble")
    let driver = DriverHeader & "\nconst content = " & tripleQuote(nimDep) & """

static:
  let got = parseNimbleRequires(content)
  doAssert got == @["other"], "got=" & $got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "parseNimbleRequires dedupes case-sensitive duplicate packages":
    # If the same package appears twice on separate lines, the parser
    # must keep only one entry (case-sensitive match). `Foo` and `foo`
    # are distinct.
    let dupContent = """requires "dup"
requires "dup >= 1.0"
requires "Dup"
"""
    let driver = DriverHeader & "\nconst content = " & tripleQuote(dupContent) & """

static:
  let got = parseNimbleRequires(content)
  doAssert got == @["dup", "Dup"], "got=" & $got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "mergeExtraRequires dedup-unions -d:tripwireAuditFFIExtraRequires with auto set":
    # The extras define carries `foo,baz`. Auto set is `@["foo", "qux"]`.
    # Result: `foo` dedup'd, `qux` preserved, `baz` appended. Order:
    # auto entries first (preserved), then extras in CSV order.
    let driver = DriverHeader & """
static:
  let got = mergeExtraRequires(@["foo", "qux"])
  doAssert got == @["foo", "qux", "baz"], "got=" & $got
"""
    let path = writeDriver(driver)
    let cmd = "nim c --compileOnly --hints:off --path:" & quoteShell(SrcPath) &
      " -d:tripwireAuditFFI -d:tripwireAuditFFITransitive" &
      " -d:tripwireAuditFFITestHook" &
      " -d:tripwireAuditFFIExtraRequires:\"foo,baz\" " &
      quoteShell(path) & " 2>&1"
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = execCmdEx(cmd)
    if code != 0: echo output
    check code == 0

  test "mergeExtraRequires returns auto set unchanged when the define is empty":
    # Regression guard: when -d:tripwireAuditFFIExtraRequires is unset
    # (or empty), the auto set passes through identically.
    let driver = DriverHeader & """
static:
  let got = mergeExtraRequires(@["foo", "qux"])
  doAssert got == @["foo", "qux"], "got=" & $got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "findFirstNimble returns a .nimble file from a populated fixture dir":
    # The fixture dir contains multiple `.nimble` files. findFirstNimble
    # returns the FIRST one discovered (walkDir order is OS-dependent
    # but deterministic within a run). We assert the result ends with
    # `.nimble` and is an absolute path into the fixture dir — not a
    # specific filename, because walkDir iteration order is not
    # guaranteed stable across Nim versions.
    let driver = DriverHeader & "\nconst fixtureDir = " & '"' & FixtureDir & '"' & "\n" & """
static:
  let got = findFirstNimble(fixtureDir)
  doAssert got.endsWith(".nimble"), "got=" & got
  doAssert got.startsWith(fixtureDir), "got=" & got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "findFirstNimble returns empty string when dir contains no .nimble files":
    # Negative case: `empty_dir` under fixtures contains only a `.keep`
    # marker, no `*.nimble`. Must return "".
    let driver = DriverHeader & "\nconst emptyDir = " & '"' & (FixtureDir / "empty_dir") & '"' & "\n" & """
static:
  let got = findFirstNimble(emptyDir)
  doAssert got == "", "got=" & got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "locatePackageDir finds pkgs2 match first (preferred over pkgs)":
    # Mock layout: `mock_pkgs/pkgs2/foo-1.0/` exists. Passing the mock
    # root via the `roots` parameter, `foo` resolves to that path.
    let driver = DriverHeader & "\nconst mockRoot = " & '"' & (FixtureDir / "mock_pkgs") & '"' & "\n" & """
static:
  let got = locatePackageDir("foo", @[mockRoot])
  doAssert got.endsWith("foo-1.0"), "got=" & got
  doAssert "pkgs2" in got, "expected pkgs2 preference, got=" & got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "locatePackageDir falls back to pkgs when pkgs2 has no match":
    # `legacy` exists only under `mock_pkgs/pkgs/legacy-2.0/`. The
    # pkgs2 layer is searched first and misses; pkgs layer hits.
    let driver = DriverHeader & "\nconst mockRoot = " & '"' & (FixtureDir / "mock_pkgs") & '"' & "\n" & """
static:
  let got = locatePackageDir("legacy", @[mockRoot])
  doAssert got.endsWith("legacy-2.0"), "got=" & got
  doAssert "pkgs" in got and "pkgs2" notin got, "expected pkgs fallback, got=" & got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0

  test "locatePackageDir returns empty string for unknown package":
    # Not-found: no `bogus-*` dir in either pkgs2 or pkgs.
    let driver = DriverHeader & "\nconst mockRoot = " & '"' & (FixtureDir / "mock_pkgs") & '"' & "\n" & """
static:
  let got = locatePackageDir("bogus", @[mockRoot])
  doAssert got == "", "got=" & got
"""
    let path = writeDriver(driver)
    var output: string
    var code: int
    {.noRewrite.}:
      (output, code) = compileDriver(path)
    if code != 0: echo output
    check code == 0
