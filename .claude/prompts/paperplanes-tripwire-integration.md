---
mission: Use paperplanes to stress-test and improve tripwire as a draft library
repos:
  tripwire: /Users/eek/Development/tripwire     # github.com/elijahr/tripwire (not on nimble registry)
  paperplanes: /Users/eek/Development/paperplanes
status: tripwire is a DRAFT — actively shape it through this work
---

# Mission

`tripwire` is a draft. Not released. Not on the nimble registry. The `v0.0.1`
tag is a checkpoint, not a contract. `paperplanes` is the first real-world
consumer, and the goal of this session is **two-way improvement**:

1. Wire `tripwire` into `paperplanes`' test suite so it actually enforces the
   three guarantees on real code (every external call pre-authorized; every
   recorded interaction explicitly asserted; every registered mock consumed).
2. Use the integration as a forcing function to make `tripwire` good. The
   library should be ergonomic, delightful, intuitive. The docs should be
   excellent. If something is rough, fix it in tripwire — don't just route
   around it in paperplanes.

The integration is the lens, but the deliverable is **a better tripwire** and
**a paperplanes test suite that genuinely benefits from it**, in that order.

# Authority

The operator (sole maintainer of both repos) grants full authority to:

- Edit, refactor, rename, move, or delete code in `tripwire`.
- Add missing features, plugins, or APIs.
- Rewrite docs from scratch where needed (follow the project's doc-writing
  skills — clarity, examples, no hand-waving).
- Change public API surface where it improves UX. Update the changelog.
- Cut new tags (`v0.0.2`, `v0.1.0`, etc.) when a coherent set of changes
  warrants it.
- Reshape directory structure, plugin layout, error messages, defect names —
  anything that makes the library more intuitive.

The operator is open to suggestions and expects them. Surface design smells
even if you're not asked. "This name is wrong" / "this API is awkward" /
"this doc is missing" are first-class observations to act on, not just log.

# Non-goals / guardrails

- **Don't break `paperplanes`.** Currently-passing tests must stay green
  after the integration. If a test can't be ported cleanly, leave it on the
  existing harness and document why in the journal.
- **Capital-preservation discipline still applies in `paperplanes`.** The
  test suite gates real-money trading logic — tripwire integration must not
  weaken any safety-test coverage. If tripwire's API would force a less
  rigorous test, that's a tripwire problem to fix, not a paperplanes
  compromise to accept.
- **Repo conventions on commits/PRs:** no AI attribution, no `Co-Authored-By`,
  no "Generated with Claude" footers, no GitHub issue references in
  messages. Applies to both repos. (Paperplanes' `CLAUDE.md` is explicit;
  treat tripwire the same unless its own `AGENTS.md` says otherwise — read
  it first.)
- **Don't downgrade scope to satisfy tooling.** If tripwire can't yet track
  `chronos` futures and paperplanes uses chronos heavily, the answer is
  "make tripwire track chronos futures," not "convert paperplanes to
  asyncdispatch." Production code in paperplanes is settled (see its
  `CLAUDE.md` Settled Decisions). Tripwire bends to fit, not the other way
  around — unless the integration uncovers a genuinely better design for
  paperplanes that the operator agrees to.

# Dependency wiring

During development, use a `nimble develop` link from paperplanes to the
local `tripwire` checkout — that's the right loop while tripwire is being
actively edited.

For the final committed state of `paperplanes.nimble`, the dependency line
should pin to a tag in the github repo:

```nim
requires "https://github.com/elijahr/tripwire.git#vX.Y.Z"
```

…where `vX.Y.Z` is whatever tag the work lands on (cut a new one if the
shape has changed meaningfully). Path-installs are fine during development;
they should not be the merged state.

# Required reading before touching anything

1. `tripwire/AGENTS.md` and `tripwire/CLAUDE.md` (if present) — tripwire's
   own conventions.
2. `tripwire/README.md` — current state of the three guarantees, scope, what
   exists today. Note what's clear and what isn't; the README is part of
   the UX and is in scope to rewrite.
3. `tripwire/docs/` — quickstart, plugin authoring, anything else. Same
   posture: read critically, fix what's wrong.
4. `tripwire/CHANGELOG.md` — what's landed, what's pending.
5. `tripwire/src/` and `tripwire/tests/` — actual API surface. Don't trust
   docs over code; verify both.
6. `paperplanes/CLAUDE.md` and `paperplanes/AGENTS.md` — paperplanes'
   conventions, settled decisions, prime directive.
7. The current live design doc in `paperplanes/docs/design/` and the most
   recent journal entries in `paperplanes/docs/journal/`.

# Phase 0 — Discovery (read-only)

Produce a discovery document at
`~/.local/spellbook/docs/Users-eek-Development-paperplanes/understanding/tripwire-integration-understanding.md`
covering both repos:

**paperplanes side:**
- Test framework (std/unittest, unittest2, balls, custom), file count, how
  the test command is wired in `paperplanes.nimble`.
- External surface that needs sandboxing: HTTP, filesystem, subprocess,
  DB, FFI (`{.importc.}` / `{.dynlib.}` / `{.header.}`), sockets, time,
  env. Catalogue per category with concrete file:line citations.
- Async / threading shape (`std/asyncdispatch`, `chronos`, threads, ARC/ORC).
- Memory manager from `nim.cfg` / `config.nims`.

**tripwire side:**
- Actual current API surface (sandbox blocks, mock DSL, async helpers,
  thread helpers, FFI audit, plugin registry). What docs claim vs. what
  the code provides.
- Plugin coverage: which external surfaces have plugins; which would
  paperplanes need that don't exist yet.
- Known rough edges: unclear errors, awkward names, missing docs, dead
  code, half-finished features. First-pass list — you'll find more during
  execution.
- Compile-time machinery and any conflicts you'd expect with paperplanes'
  build (other `--import:` directives, custom NimScript tasks, pragma
  rewriters).

**Cross-cutting:**
- Memory-manager / `--threads:on` compatibility.
- A first-pass list of changes you'd recommend to tripwire — bugs,
  renames, missing features, doc gaps, refactors.

Stop after Phase 0. Show the discovery doc. Wait for human review.

# Phase 1 — Plan (read-only)

Produce
`~/.local/spellbook/docs/Users-eek-Development-paperplanes/plans/YYYY-MM-DD-tripwire-integration-plan.md`:

1. The two parallel workstreams: (a) tripwire improvements, (b)
   paperplanes integration. Show their dependency order — which tripwire
   changes need to land before which paperplanes test can be migrated.
2. The dependency line for `paperplanes.nimble` (final form, post-tag).
3. The activation defines / imports for `paperplanes/config.nims` and
   `paperplanes/tests/config.nims`.
4. Migration order: which paperplanes test first, why, what surface it
   proves, what tripwire change (if any) it depends on.
5. Custom plugins to author in tripwire (not in paperplanes — plugins
   belong in the library when they're general, in the consumer only when
   they're truly project-specific).
6. Memory-manager / `--threads:on` decision.
7. Doc rewrites planned for tripwire. Which docs, what shape, why the
   current ones fall short.
8. Per-task acceptance criteria. "Done" = the right defects fire when
   expected and don't fire when not expected; the doc reads cleanly to a
   first-time user; the API survives the "would I want to write this?"
   test.
9. New tag plan: at what milestone does tripwire cut `v0.0.2` /
   `v0.1.0`, and what goes in each.

Stop after Phase 1. Show the plan. Wait for human review.

# Phase 2 — Execute

Per task, the loop is:

1. Read the source under test (paperplanes) AND the relevant tripwire
   surface.
2. If tripwire's surface is rough — bad name, unclear error, missing
   feature, sparse doc — fix tripwire FIRST. Commit in the tripwire repo
   with a clear message. Update the changelog.
3. Wire / migrate the paperplanes test.
4. Run targeted tests. Confirm green.
5. Verify the guarantee, not just the green: deliberately break a mock
   (wrong value, unconsumed mock, missing assertion) and confirm tripwire
   fires the expected defect with a clear message. If the message isn't
   clear, that's a tripwire bug — go fix it.
6. Run the full paperplanes test suite. Confirm green.
7. Commit per task in the relevant repo with a scope-clear message.

Tripwire commits and paperplanes commits are independent. Don't bundle.
Each repo's history should read cleanly on its own.

When you find tripwire defects: fix them. When you find tripwire UX
papercuts: smooth them. When you find tripwire docs that don't match the
code: rewrite the doc OR fix the code, whichever is right. The findings
file from the original draft of this prompt is **not** the deliverable —
fixed code and improved docs are. A short retrospective at the end is
fine; a backlog of "things future-me should fix" is not.

# Phase 3 — Sweep + report

After all planned tasks:

1. Full paperplanes test suite green.
2. Run `-d:tripwireAuditFFI` (or the current name; if it's wrong, rename
   it) over paperplanes once. Sanity-check the count.
3. Pick one external surface and verify all three guarantees end-to-end
   in a throwaway branch: unmocked call → `UnmockedInteractionDefect`;
   unconsumed mock → matching defect; unasserted interaction → matching
   defect. If any of these is awkward to demonstrate, that's the next
   tripwire fix.
4. Decide: does tripwire deserve a new tag now? If yes, cut it, update
   the changelog, update paperplanes' nimble pin to the new tag.
5. Open one PR per repo:
   - `paperplanes`: tests now use tripwire; production code unchanged
     unless an actual bug was found.
   - `tripwire`: the improvements made during integration, with a
     changelog entry and any new tag.
6. Short retrospective in `paperplanes/docs/journal/` — what worked,
   what was friction, what the next tripwire iteration should focus on.

# Surfaces to exercise where they fit paperplanes

Tick as you go:

- [ ] `sandbox: body`
- [ ] `sandbox "label": body` with the label visible in a deliberately
      failed defect message
- [ ] `mock.expect ...: respond ...`
- [ ] `assertX(..., responded: ...)`
- [ ] Worker thread helpers (only if paperplanes has worker threads on
      ARC/ORC — paperplanes is `--mm:arc`, so this should be live)
- [ ] `chronos` future tracking — paperplanes uses chronos heavily. If
      tripwire doesn't track chronos futures yet, that's a feature to add
      in tripwire, not a reason to skip the test.
- [ ] FFI audit
- [ ] Custom plugin authoring — only when the surface is paperplanes-
      specific. General-purpose plugins (HTTP, FS, subprocess, sockets,
      time, env) belong in `tripwire/src/tripwire/plugins/`.

# Deliverables

1. Green paperplanes test suite using tripwire as the test gate.
2. The discovery doc (Phase 0).
3. The integration plan (Phase 1).
4. Tangible improvements committed to tripwire: bug fixes, renames,
   refactors, new features, rewritten docs. Changelog updated. A new tag
   if warranted.
5. One PR against `paperplanes` (tests-only, ideally).
6. One PR against `tripwire` containing the improvements.
7. A brief retrospective journal entry in paperplanes covering what
   tripwire still needs before it deserves a wider audience.

# Operating principles

- Integration is the lens; ergonomic tripwire is the deliverable.
- If you have to fight the library, fix the library.
- If a doc is wrong, rewrite it; don't work around it.
- "Findings file" is not a substitute for fixing things.
- Production code in paperplanes is settled — the test harness is what
  changes. Touch production code only for genuine bugs surfaced by the
  new tests.
- Capital preservation in paperplanes is non-negotiable. Tripwire's job
  is to make that posture *easier* to enforce, not harder.
