# Tripwire v0.2 — Next Session Kickoff

Paste the block below into a fresh Claude Code session at `/Users/eek/Development/tripwire`.

---

Tripwire v0.2 Phase 4 implementation. The develop workflow's Phase 0-3 is
complete: design doc, implementation plan (rev-2 APPROVED), and 5 chunk
prompt files have all been generated.

Start the first chunk now. Follow the prompt in
`.claude/prompts/tripwire-v0.2-chunk-1.md` (WI1 — FFI audit auto-discovery,
Tasks 1.1-1.6, independent, ~6 tasks).

The chunk file will tell you to invoke the `develop` skill with the
escape hatch "impl plan, treat as ready" so the workflow enters at Phase 4
directly. Per-task gate sequence (TDD → completion verification → code
review → fact-checking) and post-all-tasks gates (audit → tests → green
mirage → fact-check) are mandatory and explicitly enumerated in the
chunk file.

Session preferences:
- autonomous_mode: autonomous
- parallelization: maximize
- worktree: none (trunk-based on `main`)
- post_impl: offer_options
- dialectic_mode: none
- token_enforcement: gate_level
- complexity_tier: complex

When Chunk 1 is committed, its `Next` section will direct you to
Chunk 2. Chunks 3 and 4 may run in parallel sessions after Chunk 2
lands; Chunk 5 requires both 3 and 4 complete.

Key artifacts:
- Implementation plan: `~/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-impl.md`
- Design doc: `~/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-design.md`
- Understanding doc: `~/.local/spellbook/docs/Users-eek-Development-tripwire/understanding/understanding-tripwire-v0.2-2026-04-23.md`
- Chunk prompts: `.claude/prompts/tripwire-v0.2-chunk-{1..5}.md`

Proceed.
