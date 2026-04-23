## tripwire/audit_ffi.nim — Defense 2 Part 3 FFI pragma audit scanner.
##
## When built with `-d:tripwireAuditFFI`, walks a configurable set of
## filesystem paths at compile time and emits a `{.hint.}` report
## enumerating every `{.importc.}`, `{.importcpp.}`, `{.importobjc.}`,
## and `{.importjs.}` pragma it finds. The report distinguishes
##
##   Direct FFI       — pragmas in the user's own source tree
##                       (TRIPWIRE_FFI_SCAN_PATHS; default: "src")
##   Transitive FFI   — pragmas in imported code outside the user's tree
##                       (TRIPWIRE_FFI_TRANSITIVE_PATHS; default: empty)
##
## Both path lists are comma-separated. If TRIPWIRE_FFI_TRANSITIVE_PATHS
## is empty, the scanner reports "transitive FFI: 0 (not scanned — set
## TRIPWIRE_FFI_TRANSITIVE_PATHS to include the Nim stdlib dir or a
## nimble deps dir)" instead of silently reporting zero. This is an
## honest Option-D scope per the v0 design doc Appendix B: a full
## transitive macro-driven walk requires compiler-internal APIs that
## are not stable across Nim versions.
##
## Mechanism: `staticExec` drives a POSIX-portable `grep -rE` over the
## supplied directories, piped through `awk` to count pragma occurrences
## per file. The regex requires the pragma-start delimiter `{.` so
## plain-text mentions of `importc` in comments and string literals are
## not counted. Multi-pragma lines (`{.importc, dynlib.}`) count once
## per FFI-pragma keyword on the line.
##
## Defense 2 has three parts in the design:
##   Part 1: FFI-scope footer on every defect message (errors.nim).
##   Part 2: opt-in activation gate for `import tripwire` (facade).
##   Part 3: this scanner.
##
## See `docs/design/v0.md` §11.2 Part 3 and Appendix B.
when defined(tripwireAuditFFI):
  import std/[strutils, os]

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

  const
    directPathsRaw {.used.} = staticExec("printenv TRIPWIRE_FFI_SCAN_PATHS")
    transitivePathsRaw {.used.} = staticExec("printenv TRIPWIRE_FFI_TRANSITIVE_PATHS")

  const
    directPaths = (if directPathsRaw.strip().len == 0: "src" else: directPathsRaw.strip())
    transitivePaths = transitivePathsRaw.strip()

  const
    directRaw = staticExec(tripwireFfiScanCommand(directPaths))
    transitiveRaw =
      if transitivePaths.len == 0: ""
      else: staticExec(tripwireFfiScanCommand(transitivePaths))

  const
    directParsed = tripwireFfiParseReport(directRaw)
    transitiveParsed = tripwireFfiParseReport(transitiveRaw)

  const ffiReport = block:
    var r = "\ntripwire FFI audit (Defense 2 Part 3)\n"
    r.add "=====================================\n"
    r.add "Direct FFI (paths: " & directPaths & ")\n"
    if directParsed.perFile.len > 0:
      r.add directParsed.perFile & "\n"
    r.add "  Direct total: " & $directParsed.total & "\n"
    r.add "\n"
    if transitivePaths.len == 0:
      r.add "Transitive FFI: 0 (not scanned -- set TRIPWIRE_FFI_TRANSITIVE_PATHS " &
        "to a comma-separated list of dirs, e.g. the Nim stdlib path, to enable)\n"
    else:
      r.add "Transitive FFI (paths: " & transitivePaths & ")\n"
      if transitiveParsed.perFile.len > 0:
        r.add transitiveParsed.perFile & "\n"
      r.add "  Transitive total: " & $transitiveParsed.total & "\n"
    r.add "\n"
    r.add "Grand total: " & $(directParsed.total + transitiveParsed.total) & "\n"
    r

  {.hint: ffiReport.}
