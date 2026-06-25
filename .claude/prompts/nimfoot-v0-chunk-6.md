# nimfoot v0 - Chunk 6/8: Plugins (Track F)

## Working Directory

**Path:** /Users/eek/Development/nimfoot
**Branch:** main (no worktree — work in current directory)

BEFORE ANY WORK:
1. `cd /Users/eek/Development/nimfoot && pwd && git branch --show-current`
2. Verify output shows `main` (Chunk 1 must have run `git init` if not a repo)
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/nimfoot`
4. Do NOT create new branches or switch branches

## Context

This is the **Plugins** chunk (Track F). Tasks depend on **Chunk 1 (A-track foundation)**, **Chunk 3 (C1 async helpers)**, and **Chunk 4 (D1 macros, D2 cap counter)**.

Tasks in this chunk — 8 total, **with strict file-serial ordering**:

- **F1** — `MockPlugin` type + registration (`src/nimfoot/plugins/mock.nim`). Depends on A2, A3, A3.6, A4, A6, A7, D1.
- **F2** — `MockPlugin` `expect` DSL macro. Depends on F1.
- **F3** — `MockPlugin` `assert` DSL macro. Depends on F2.
- **F4** — `httpclient` plugin — base types + sync `request` TRM (`src/nimfoot/plugins/httpclient.nim`). Depends on A7, C1, D1.

  **RISK — F4 is the critical-path plugin probe.** Per the plan (Section "TRM pattern-binding citation" around line 3073 of the impl plan), the 6-arg pattern `requestSyncTRM*{request(c, url, httpMethod, body, headers, multipart)}(...)` MUST bind `c.request("http://a")` (a 1-arg call + 5 stdlib defaults). Per spike #3 finding 7, stdlib defaults elaborate pre-TRM. **Before investing in the full TRM + plugin scaffolding, write the throwaway 5-line TRM smoke probe described around impl plan line 3120** to verify the assumption. If the smoke probe fails, STOP and consult user — the plugin must re-architect per verb (`get`, `post`, …) instead of `request`.

- **F5** — httpclient async TRM + remaining sync TRMs (Uri variant, newHttpClient, close, downloadFile). Depends on F4. **Serial-with F4** (both edit `src/nimfoot/plugins/httpclient.nim`).
- **F6** — httpclient wrapper canonicalization (`expect get(...)` → `request` mock). Depends on F4. **Serial-with F5** (both edit `src/nimfoot/plugins/httpclient.nim`).
- **F7** — osproc plugin — `execProcess` + seq TRM + fake `Process` scaffolding (`src/nimfoot/plugins/osproc.nim`). Depends on A7, D1, D2.
- **F8** — osproc array-variant TRMs + fallback trap (**Defense 5**). Depends on F7. **Serial-with F7** (both edit `src/nimfoot/plugins/osproc.nim`).

Required within-track sequence: **F1 → F2 → F3 → F4 → F5 → F6 → F7 → F8**. The file-serial pairs (F4/F5/F6 on `httpclient.nim` and F7/F8 on `osproc.nim`) are strict — do NOT parallelize within these chains.

Previous chunks completed: **Chunk 1 (Track A), Chunk 3 (Track C), Chunk 4 (Track D)**. Chunk 5 (Track E) is NOT a strict prerequisite per the dep graph — the plugins depend on D/A/C but not on E — but Chunk 5 may have landed in parallel.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md, treat as ready. Tasks F1, F2, F3, F4, F5, F6, F7, F8 (plugins: mock, httpclient, osproc). Honor file-serial ordering: F4→F5→F6 on httpclient.nim, F7→F8 on osproc.nim. Before F4 implementation: run the 5-line TRM smoke probe described around line 3120 of the impl plan; if it fails, STOP and escalate. Fully autonomous."
```

**Key documents:**
- Implementation plan: /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md
- Design document: /Users/eek/Development/nimfoot/docs/design/v0.md
- Mirror design doc: /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-design.md

## Subagent Dispatch Discipline

<CRITICAL>
The develop skill orchestrates via subagents. Every subagent that does substantive work MUST invoke the appropriate skill using the Skill tool.

"Do TDD" is NOT the same as "invoke the test-driven-development skill."
"Review the code" is NOT the same as "invoke the requesting-code-review skill."
Doing the work without invoking the skill is a workflow violation.

Every subagent prompt MUST begin with:
  "First, invoke the [skill-name] skill using the Skill tool. Then follow its complete workflow."

After each subagent returns, verify its output contains "Launching skill: [name]". If not found, re-dispatch with explicit instruction to invoke the skill.
</CRITICAL>

### Per-Task Gate Sequence (mandatory, sequential, not batched)

After EACH task (F1, F2, F3, F4, F5, F6, F7, F8), run these gates in order:

1. **TDD** (4.3): Dispatch subagent → must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent → must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent → must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. Each task completes all 4 gates before the next task begins.

**F4 pre-task addendum:** Before the TDD RED phase for F4, run the smoke-probe described at line 3120 of the impl plan. If the probe fails, STOP and escalate before writing any F4 test or code.

### Post-Chunk Gates (after all F tasks pass per-task gates)

1. Run `nimble test` from `/Users/eek/Development/nimfoot` — all tests must pass.
2. Commit chunk completion with message `plugins: implement tasks F1-F8 (mock, httpclient, osproc)`

## Pre-conditions

- Chunk 1 committed to `main`: full Track A foundation
- Chunk 3 committed to `main`: `futures.nim` (C1) exists
- Chunk 4 committed to `main`: `macros.nim` (D1) and `cap_counter.nim` (D2) exist
- Working tree clean before starting F1
- `nimble test` passes on the latest commit baseline

## Exit Criteria

- Tasks F1 through F8 complete with all 4 per-task gates passed
- `src/nimfoot/plugins/mock.nim`, `src/nimfoot/plugins/httpclient.nim`, `src/nimfoot/plugins/osproc.nim` all exist
- F4 smoke probe documented in the commit body or companion note (pass/fail captured)
- Defense 5 fallback trap lands with F8 and is exercised by a test
- All chunk tests passing (`nimble test` clean)
- Chunk commit created on `main` with message `plugins: implement tasks F1-F8 (mock, httpclient, osproc)`
- Working tree clean

## Next

When complete, run the next chunk:
```
Follow the prompt in /Users/eek/Development/nimfoot/.claude/prompts/nimfoot-v0-chunk-7.md
```
