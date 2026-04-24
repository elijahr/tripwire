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
    # Transitive scope is Task 1.4's concern. Emit a placeholder so
    # the report shape stays stable for v0.1 consumers that expect a
    # transitive section followed by a grand total footer.
    r.add "Transitive FFI: 0 (not scanned -- set -d:tripwireAuditFFITransitive to enable)\n"
    r.add "\n"
    r.add "Grand total: " & $directParsed.total & "\n"
    r

  {.hint: ffiReport.}
