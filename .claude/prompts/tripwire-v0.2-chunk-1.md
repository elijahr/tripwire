# Tripwire v0.2 — Chunk 1/5: FFI audit auto-discovery (WI1)

## Working Directory

**Path:** `/Users/eek/Development/tripwire`
**Branch:** `main`

BEFORE ANY WORK:
1. `cd /Users/eek/Development/tripwire && pwd && git branch --show-current`
2. Verify output shows `main`
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/tripwire`
4. Do NOT create new branches or switch branches (trunk-based; session preference `worktree: none`)

## Context

This chunk lands Work Item 1 of Tripwire v0.2: the FFI audit auto-discovery refactor. It removes the v0.1 environment-variable contract (`TRIPWIRE_FFI_SCAN_PATHS`, `TRIPWIRE_FFI_TRANSITIVE_PATHS`) from `audit_ffi.nim` and replaces it with `querySetting(projectPath)` auto-discovery plus an opt-in `-d:tripwireAuditFFITransitive` path that parses `.nimble` `requires` lines. This is the only v0.2 workstream that does NOT touch `sandbox.nim`; landing it first de-risks the shared-field coordination between WI3 and WI4.

Previous chunks completed: none (this is the first chunk; WI1 is independent of WI2/3/4/5 structurally).

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-impl.md, treat as ready. Tasks 1.1-1.6 (Work Item 1). Fully autonomous."
```

**Key documents:**
- Implementation plan: `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-impl.md`
- Design document: `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-design.md`
- Understanding document: `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/understanding/understanding-tripwire-v0.2-2026-04-23.md`

## Subagent Dispatch Discipline

<CRITICAL>
The develop skill orchestrates via subagents. Every subagent that does
substantive work MUST invoke the appropriate skill using the Skill tool.

"Do TDD" is NOT the same as "invoke the test-driven-development skill."
"Review the code" is NOT the same as "invoke the requesting-code-review skill."
Doing the work without invoking the skill is a workflow violation.
Skills contain specialized logic that ad-hoc execution cannot replicate.

Every subagent prompt MUST begin with:
  "First, invoke the [skill-name] skill using the Skill tool.
   Then follow its complete workflow."

After each subagent returns, verify its output contains
"Launching skill: [name]". If not found, re-dispatch with explicit
instruction to invoke the skill.
</CRITICAL>

### Per-Task Gate Sequence (mandatory, sequential, not batched)

After EACH task, run these gates in order:

1. **TDD** (4.3): Dispatch subagent -> must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent -> must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent -> must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. Each task completes all 4 gates before
the next task begins.

### Post-All-Tasks Gates (mandatory, end of this chunk)

After all tasks in this chunk pass per-task gates:

1. Comprehensive implementation audit (4.6.1) — inline audit prompt
2. Full test suite (4.6.2) — dispatch subagent to run `nimble test` across matrix cells 1-6 (the v0.1 baseline; cell #7 is introduced by WI3)
3. Green mirage audit (4.6.3) -> must invoke `auditing-green-mirage` skill using the Skill tool
4. Comprehensive fact-checking (4.6.4) -> must invoke `fact-checking` skill using the Skill tool

## Pre-conditions

- `git status` on `/Users/eek/Development/tripwire` reports no changes except the untracked `.claude/` dir
- Current branch is `main` at commit `52d5c81` (or later, if HEAD has advanced — verify via `git log --oneline -1`)
- `nim --version` reports 2.2.x
- Matrix baseline: `nimble test` exits 0 across 5 active cells (601 OK); cell #6 `osproc_arrays` may be skipped per `tripwire.nimble` line 27
- `src/tripwire/audit_ffi.nim:118-156` currently reads `TRIPWIRE_FFI_SCAN_PATHS` / `TRIPWIRE_FFI_TRANSITIVE_PATHS` via `staticExec("printenv ...")` (confirm via grep before starting)
- `.claude/prompts/` directory exists

## Exit Criteria

- All Tasks 1.1 through 1.6 acceptance criteria met, each landed as its own commit on `main`
- All per-task gates passed (TDD RED+GREEN, completion verify, code review, fact-check) for Tasks 1.2, 1.3, 1.4, 1.5, 1.6; Task 1.1 is doc-only (code review only, no TDD)
- `src/tripwire/audit_ffi.nim` no longer depends on `TRIPWIRE_FFI_SCAN_PATHS` or `TRIPWIRE_FFI_TRANSITIVE_PATHS`; direct scope works via `querySetting(projectPath)` with F3 empty-projectPath fallback to `getCurrentDir()`
- `-d:tripwireAuditFFITransitive` opt-in wires per-package aggregation from `.nimble` `requires` parsing
- `-d:tripwireAuditFFIExtraRequires:"pkg1,pkg2"` escape hatch de-duplicates against auto-detected set
- `git grep 'TRIPWIRE_FFI_'` returns zero matches in `src/` and `tests/`
- New test files `tests/audit_ffi/test_auto_projectpath.nim`, `tests/audit_ffi/test_nimble_parser_limits.nim`, `tests/audit_ffi/test_auto_transitive_optin.nim`, `tests/audit_ffi/test_stdlib_not_scanned.nim` exist and pass (stdlib-never-scanned negative guard included)
- Updated `tests/test_audit_ffi.nim` reflects new API and passes
- `tests/all_tests.nim` imports the new `tests/audit_ffi/*.nim` files (per Task 1.6)
- `notes/wi1-v0.1-baseline.md` exists at `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/notes/wi1-v0.1-baseline.md` and is committed
- `nimble test` passes all 6 pre-existing matrix cells
- Metrics achieved: M3 (FFI auto-discovery works), M3b (stdlib never scanned, even under transitive flag)
- Quality gates passed (comprehensive audit, full test suite, green mirage, fact-check)

## Next

When complete, run the next chunk:
```
Follow the prompt in .claude/prompts/tripwire-v0.2-chunk-2.md
```
