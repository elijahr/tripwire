## tripwire/audit_ffi.nim — Defense 2 Part 3 FFI pragma audit scanner.
##
## When built with `-d:tripwireAuditFFI`, walks the project's source
## tree at compile time and emits a `{.hint.}` report enumerating
## every `{.importc.}`, `{.importcpp.}`, `{.importobjc.}`, and
## `{.importjs.}` pragma it finds. The report distinguishes
##
##   Direct FFI       — pragmas in the user's own source tree,
##                       auto-discovered via
##                       `querySetting(SingleValueSetting.projectPath)`.
##   Transitive FFI   — pragmas in imported code outside the user's
##                       tree. Opt-in via `-d:tripwireAuditFFITransitive`
##                       (wired in Task 1.4; this module emits a
##                       placeholder line when the define is absent).
##
## v0.2 replaces the v0.1 env-var contract with compiler-driven
## auto-discovery (design §5.2, §5.2.1; see CHANGELOG for the
## migration note). The F3 fallback: if `projectPath` resolves
## to an empty string, emit a compile-time warning and fall back
## to `getCurrentDir()`. projectPath is always set under `nim c`;
## the fallback is defensive only.
##
## Mechanism: `staticExec` drives a POSIX-portable `grep -rE` over the
## discovered directory, piped through `awk` to count pragma
## occurrences per file. The regex requires the pragma-start delimiter
## `{.` so plain-text mentions of `importc` in comments and string
## literals are not counted. Multi-pragma lines (`{.importc, dynlib.}`)
## count once per FFI-pragma keyword on the line.
##
## Defense 2 has three parts in the design:
##   Part 1: FFI-scope footer on every defect message (errors.nim).
##   Part 2: opt-in activation gate for `import tripwire` (facade).
##   Part 3: this scanner.
##
## See `docs/design/v0.md` §11.2 Part 3 and Appendix B.
when defined(tripwireAuditFFI):
  import std/[strutils, os, compilesettings]

  const FFIPragmaRegex = """\{\.[[:space:]]*(importc|importcpp|importobjc|importjs)"""
    ## Anchored at the pragma-start delimiter `{.` so string literals
    ## and `##` doc comments mentioning `importc` are not matched.
    ## `[[:space:]]*` tolerates `{.  importc .}` formatting. The
    ## keyword is followed by EOL-or-delimiter naturally (next char is
    ## `:`, `,`, `.`, or space); no trailing anchor needed because the
    ## four keywords have no common prefix with other valid pragmas.

  proc tripwireFfiScanCommand(paths: string): string {.compileTime.} =
    ## Build a shell command that prints one `<path>:<count>` line per
    ## .nim file found under the comma-separated `paths`, with `count`
    ## being the number of FFI-pragma matches in that file. Empty
    ## `paths` -> empty command that produces empty output.
    if paths.len == 0:
      return "true"  # no-op; staticExec returns empty string
    # Split on comma, space-join as find arguments. Each entry is
    # shell-quoted so spaces and special chars in repo paths don't
    # break the command.
    var findArgs = ""
    for p in paths.split(','):
      let trimmed = p.strip()
      if trimmed.len == 0: continue
      if findArgs.len > 0: findArgs.add ' '
      findArgs.add quoteShell(trimmed)
    if findArgs.len == 0:
      return "true"
    # `find ... -name '*.nim'` -> list of files.
    # `xargs grep -cE` -> per-file match count. `-c` prints 0 for files
    #   with no matches, `-E` enables the extended regex.
    # `-H` is implicit when multiple files are supplied; we use `grep
    #   -c` with `/dev/null` appended to force `file:count` even when
    #   only one file matches.
    # Using `sh -c` would require double-escaping; instead pipe through
    # awk that keeps lines where count > 0 (for the report) plus a
    # SUM line for the grand total. Zero-count lines are kept so the
    # test suite can assert "c_clean.nim: 0" is either reported or
    # omitted; we keep them to make the report self-describing.
    result = "find " & findArgs &
      " -type f -name '*.nim' -print0 2>/dev/null" &
      " | xargs -0 grep -cE " & quoteShell(FFIPragmaRegex) &
      " /dev/null 2>/dev/null" &
      " | awk -F: 'BEGIN{sum=0} $1 != \"/dev/null\" {sum+=$2; print $0} END{print \"SUM:\"sum}'"

  proc tripwireFfiParseReport(raw: string): tuple[perFile: string, total: int] {.compileTime.} =
    ## Parse the shell output into a pretty per-file block plus a grand
    ## total. Input lines look like:
    ##   /path/to/foo.nim:3
    ##   /path/to/bar.nim:0
    ##   SUM:3
    ## The SUM line is authoritative for the total; summing per-file
    ## counts would duplicate awk's work and risk drift if the command
    ## shape changes.
    var perFileLines: seq[string] = @[]
    var total = 0
    for ln in raw.splitLines():
      let line = ln.strip()
      if line.len == 0: continue
      if line.startsWith("SUM:"):
        total = parseInt(line[4 .. ^1])
        continue
      let colon = line.rfind(':')
      if colon < 0: continue
      let countStr = line[colon + 1 .. ^1].strip()
      var count: int
      try:
        count = parseInt(countStr)
      except ValueError:
        continue
      # Collapse absolute path to a short suffix for readability;
      # ~4-level suffix is enough to disambiguate without dumping
      # every user's home directory path into build logs.
      let path = line[0 ..< colon]
      let short = extractFilename(path)
      if count > 0:
        perFileLines.add "  " & short & ": " & $count
      else:
        # Always include zero-count files so the scanner's coverage is
        # visible (user can confirm the file was scanned). Cheap.
        perFileLines.add "  " & short & ": 0"
    (perFileLines.join("\n"), total)

  proc scanDir(dir: string): tuple[perFile: string, total: int] {.compileTime.} =
    ## Compose `tripwireFfiScanCommand` + `staticExec` + `tripwireFfiParseReport`
    ## into a single call for one directory. Caller owns the existence
    ## guard (see `scanProjectPath` for the F3 empty-projectPath
    ## fallback); if `dir` does not exist, `find` emits no lines and
    ## the parser returns ("", 0) cleanly.
    tripwireFfiParseReport(staticExec(tripwireFfiScanCommand(dir)))

  when defined(tripwireAuditFFITransitive):
    ## Task 1.3 scaffolding for Task 1.4's per-package transitive scan
    ## (design §5.3, lines 900-1000). These helpers are gated behind
    ## the opt-in transitive define so direct-scope builds (Task 1.2's
    ## contract) are unaffected. The `{.hint.}` emission block below
    ## remains Task 1.4's concern; only the parser utilities live here.
    ##
    ## The escape hatch `-d:tripwireAuditFFIExtraRequires:"pkg1,pkg2"`
    ## is consumed by `mergeExtraRequires` -- users whose `.nimble`
    ## files trip the parser's documented limits (multi-line requires,
    ## variable expansion) can supplement the auto-detected set
    ## without modifying their package metadata.
    import std/algorithm

    const extraRequiresCSV {.strdefine: "tripwireAuditFFIExtraRequires".}: string = ""

    proc parseNimbleRequires(content: string): seq[string] {.compileTime.} =
      ## Parse `requires "pkg"` / `requires "pkg >= 1.0"` lines from
      ## the CONTENT of a `.nimble` file (not the path -- the caller
      ## is responsible for `staticRead`). Returns package names only;
      ## version bounds are stripped. Case-sensitive dedup.
      ##
      ## DOCUMENTED LIMITS (design §5.3 lines 913-931):
      ##   - Multi-line `requires "pkg1",\n   "pkg2"` forms: ONLY the
      ##     first package on the first line is captured. Continuation
      ##     lines are silently skipped.
      ##   - Variable expansion: any `requires` line containing `&`
      ##     is skipped (the parser cannot resolve runtime values at
      ##     scan time). Users supplement via -d:tripwireAuditFFIExtraRequires.
      ##   - Conditional `requires` inside `when` / `if` blocks:
      ##     INCLUDED regardless. Control flow is not evaluated --
      ##     every quoted-pkg line is picked up.
      ##   - `requires "nim"` / `requires "nim >= 2.0"`: SKIPPED. Nim
      ##     itself is not a scannable dep; stdlib is forbidden (§5.5).
      ##   - Trailing tokens after the first quoted pkg name are
      ##     SILENTLY DROPPED. e.g. `requires "foo" "bar"` yields only
      ##     `["foo"]`; any typos or stray tokens on the same line are
      ##     lost. Use one `requires` line per package to be safe.
      const kw = "requires"
      result = @[]
      for line in content.splitLines:
        let s = line.strip()
        if not s.startsWith(kw):
          continue
        # After the keyword require whitespace or an immediate quote.
        # Rejects identifiers like `requiresX` while accepting tab-
        # separated (`requires\t"pkg"`) and zero-space (`requires"pkg"`)
        # forms, both of which are unusual but syntactically valid in
        # `.nimble` files.
        if s.len <= kw.len or
           (s[kw.len] != ' ' and s[kw.len] != '\t' and s[kw.len] != '"'):
          continue
        # Variable-expansion guard (documented miss): `requires "foo" & ver`.
        # Skip the line rather than return a malformed pkg name.
        if '&' in s:
          continue
        let quoted = s.find('"')
        if quoted < 0:
          continue
        let endQuote = s.find('"', quoted + 1)
        if endQuote < 0:
          continue
        let spec = s[quoted + 1 ..< endQuote].strip()
        if spec.len == 0:
          continue
        # Strip version bound. `spec` is of the form `pkg` or
        # `pkg >= 1.0` -- split on whitespace and keep the first token.
        let pkgName = spec.split({' ', '\t'})[0].strip()
        if pkgName.len == 0:
          continue
        if pkgName == "nim":
          continue
        # Case-sensitive dedup. `foo` and `Foo` remain distinct.
        if pkgName notin result:
          result.add(pkgName)

    proc mergeExtraRequires(auto: seq[string]): seq[string] {.compileTime.} =
      ## Union the auto-detected requires set with the CSV escape hatch
      ## `-d:tripwireAuditFFIExtraRequires:"pkg1,pkg2"`. Dedup preserves
      ## auto-set order; extras append in CSV order, each skipped if
      ## already present in the auto set OR already appended from an
      ## earlier extras slot.
      result = auto
      if extraRequiresCSV.len == 0:
        return
      for extra in extraRequiresCSV.split(','):
        let pkg = extra.strip()
        if pkg.len == 0:
          continue
        if pkg notin result:
          result.add(pkg)

    proc findFirstNimble(dir: string): string {.compileTime.} =
      ## Return the absolute path to the lexicographically first
      ## `*.nimble` file in `dir` (non-recursive; top-level only).
      ## Returns "" if none. Used by Task 1.4's `scanTransitive` as a
      ## fallback when the conventional `<pkgName>.nimble` path does
      ## not resolve.
      ##
      ## Matches are collected and sorted so the result is deterministic
      ## across filesystems (APFS vs ext4 yield different `walkDir`
      ## orders).
      if not dirExists(dir):
        return ""
      var matches: seq[string] = @[]
      for kind, path in walkDir(dir, relative = false):
        if kind == pcFile and path.endsWith(".nimble"):
          matches.add(path)
      matches.sort()
      if matches.len > 0: matches[0] else: ""

    proc locatePackageDir(pkgName: string,
                          roots: seq[string] = @[]): string {.compileTime.} =
      ## Resolve an installed package name to its on-disk directory.
      ## Search order (design §5.3 lines 982-1000):
      ##   1. `<root>/pkgs2/<pkgName>-<version>-<hash>/`
      ##   2. `<root>/pkgs/<pkgName>-<version>/`
      ##   3. `<root>/<pkgName>/` (plain root; covers local installs)
      ##
      ## The `roots` parameter defaults to `[$HOME/.nimble]`. Task 1.4
      ## will replace this default with `querySettingSeq(nimblePaths)`.
      ## Tests inject a mock root to avoid touching the real `$HOME`.
      ## Returns "" if no match is found under any root / subdir.
      ##
      ## Version selection is best-effort: within a given subdir layer,
      ## matches are collected and sorted; the lexicographically LAST
      ## match wins. For semver-style names like `pkg-1.0` vs `pkg-2.0`
      ## this approximates "newest version". `walkDir` order is
      ## filesystem-dependent, so sorting is required for deterministic
      ## cross-OS behavior.
      let searchRoots =
        if roots.len > 0: roots
        else: @[getHomeDir() / ".nimble"]
      for root in searchRoots:
        for subdir in ["pkgs2", "pkgs", ""]:
          let searchRoot = if subdir.len > 0: root / subdir else: root
          if not dirExists(searchRoot):
            continue
          var matches: seq[string] = @[]
          for kind, path in walkDir(searchRoot):
            if kind != pcDir:
              continue
            let name = extractFilename(path)
            if name == pkgName or name.startsWith(pkgName & "-"):
              matches.add(path)
          if matches.len > 0:
            matches.sort()
            return matches[^1]
      ""

    proc scanTransitive(): tuple[perPkg: string, total: int] {.compileTime.} =
      ## Transitive-scope scan (design §5.3 / §5.4). Emits per-package
      ## aggregate lines (pkg name + total FFI-pragma count across the
      ## package's installed tree); no per-file breakdown. Grand
      ## aggregate is the sum of per-package totals.
      ##
      ## Steps:
      ##   1. Resolve projectDir via `querySetting(projectPath)` with
      ##      the same F3 fallback as `scanProjectPath` (empty string
      ##      -> `getCurrentDir()`).
      ##   2. Locate the `.nimble` under projectDir via
      ##      `findFirstNimble`. Missing `.nimble` returns ("", 0) so
      ##      the caller can still render a (empty) transitive section
      ##      alongside the direct scope. The missing-`.nimble`
      ##      warning is fired by the module-level `when` guard below
      ##      (not by this proc body) so that it only appears on the
      ##      matching compile branch -- `{.warning.}` inside a proc
      ##      fires at pragma-parse time unconditionally, which defeats
      ##      conditional diagnostics.
      ##   3. `staticRead` the `.nimble`.
      ##   4. `parseNimbleRequires` -> seq of package names.
      ##   5. `mergeExtraRequires` folds in the
      ##      `-d:tripwireAuditFFIExtraRequires:"pkg1,pkg2"` escape hatch.
      ##   6. For each pkg, `locatePackageDir(pkg, nimblePaths)` to find
      ##      the installed dir. Not-found emits a CT `echo` diagnostic
      ##      (not a pragma `{.warning.}`; see note above) and the pkg
      ##      is skipped. The `nimblePaths` roots come from
      ##      `querySettingSeq(nimblePaths)` so the scan respects the
      ##      actual nimble install locations (system nimble, mise,
      ##      vendored tool directories) without requiring
      ##      `$HOME/.nimble` to be the authoritative root.
      ##   7. `scanDir` each located dir; accumulate the per-pkg line
      ##      `"  <pkgName>: <total>\n"` and the grand transitive total.
      const projectPath = querySetting(SingleValueSetting.projectPath)
      let projectDir =
        when projectPath.len == 0:
          getCurrentDir()
        else:
          projectPath
      let nimblePath = findFirstNimble(projectDir)
      if nimblePath.len == 0:
        return ("", 0)
      let content = staticRead(nimblePath)
      let auto = parseNimbleRequires(content)
      let final = mergeExtraRequires(auto)
      const nimblePaths = querySettingSeq(MultipleValueSetting.nimblePaths)
      var lines = ""
      var grand = 0
      for pkg in final:
        let dir = locatePackageDir(pkg, nimblePaths)
        if dir.len == 0:
          echo "tripwire FFI transitive: package ", pkg,
               " not found under nimblePaths; skipped."
          continue
        let (_, total) = scanDir(dir)
        lines.add "  " & pkg & ": " & $total & "\n"
        grand += total
      (lines, grand)

    const transitiveProjectPath = querySetting(SingleValueSetting.projectPath)
    const transitiveProjectDir =
      when transitiveProjectPath.len == 0: getCurrentDir()
      else: transitiveProjectPath
    const transitiveNimblePath = findFirstNimble(transitiveProjectDir)
    when transitiveNimblePath.len == 0:
      # Load-bearing `when` guard: `{.warning.}` is a pragma statement
      # evaluated at parse time regardless of enclosing `if` control
      # flow, so it MUST sit inside a static `when` that excludes the
      # happy path. Users who see this warning know Task-1.4's
      # transitive scan found no `.nimble` under projectPath and
      # silently reverted to direct-scope coverage.
      {.warning: "tripwire FFI transitive: no .nimble found at " & transitiveProjectDir & "; transitive scope skipped.".}

    when defined(tripwireAuditFFITestHook):
      ## Test-only re-export. Production builds do NOT export these
      ## helpers -- they are internal CT utilities. The test driver in
      ## `tests/audit_ffi/test_nimble_parser_limits.nim` compiles with
      ## `-d:tripwireAuditFFITestHook` so it can `import tripwire/audit_ffi`
      ## and reach the procs below. Keeping the exports conditional
      ## preserves the right to change these signatures without a
      ## public-API break.
      export parseNimbleRequires, mergeExtraRequires, findFirstNimble, locatePackageDir

  proc scanProjectPath(): tuple[dir: string, perFile: string, total: int] {.compileTime.} =
    ## Scan the project's own source tree. Uses
    ## `querySetting(SingleValueSetting.projectPath)` (design §5.2.1)
    ## to pick up the directory containing the main compile target.
    ## F3 fallback (design §5.2 lines 848-853): if projectPath is
    ## empty, emit a compile-time warning and fall back to
    ## `getCurrentDir()`. The warning surfaces the drift so users
    ## can file an issue; the fallback keeps the build working.
    ## Returns the scanned `dir` alongside the parse result so the
    ## caller (the `{.hint.}` emission) can quote the exact path
    ## without re-querying the setting.
    const projectPath = querySetting(SingleValueSetting.projectPath)
    when projectPath.len == 0:
      {.warning: "tripwire FFI: querySetting(projectPath) returned empty; falling back to getCurrentDir(). This is unexpected under `nim c`; please report it at https://github.com/elijahr/tripwire/issues with your invocation.".}
      let cwd = getCurrentDir()
      let r = scanDir(cwd)
      (cwd, r.perFile, r.total)
    else:
      let r = scanDir(projectPath)
      (projectPath, r.perFile, r.total)

  const directParsed = scanProjectPath()

  const ffiReport = block:
    var r = "\ntripwire FFI audit (Defense 2 Part 3)\n"
    r.add "=====================================\n"
    r.add "Direct FFI (paths: " & directParsed.dir & ")\n"
    if directParsed.perFile.len > 0:
      r.add directParsed.perFile & "\n"
    r.add "  Direct total: " & $directParsed.total & "\n"
    r.add "\n"
    # Transitive section: placeholder by default; real per-package
    # aggregates when `-d:tripwireAuditFFITransitive` is set (Task 1.4,
    # design §5.3 / §5.4). The two forms are controlled by a `when`
    # branch so v0.1 consumers that grep for the placeholder keep
    # working on default builds, while opt-in consumers get the real
    # numbers.
    when defined(tripwireAuditFFITransitive):
      let transitive = scanTransitive()
      r.add "Transitive FFI (per-package aggregate, opt-in via -d:tripwireAuditFFITransitive):\n"
      if transitive.perPkg.len > 0:
        r.add transitive.perPkg
      r.add "  Transitive total: " & $transitive.total & "\n"
      r.add "\n"
      r.add "Grand total: " & $(directParsed.total + transitive.total) & "\n"
    else:
      r.add "Transitive FFI: 0 (not scanned -- set -d:tripwireAuditFFITransitive to enable)\n"
      r.add "\n"
      r.add "Grand total: " & $directParsed.total & "\n"
    r

  {.hint: ffiReport.}
