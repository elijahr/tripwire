# Contributing to Tripwire

Tripwire is early — the v0 core shipped in April 2026 and has not yet
been heavily exercised in real test suites. Bug reports, feedback, and
contributions are genuinely valued; small rough edges are expected.

## Prerequisites

- **Nim 2.2.6** — pinned. Install via [mise](https://mise.jdx.dev/),
  [choosenim](https://github.com/nim-lang/choosenim), or your OS
  package manager.
- `git`
- `nimble` (bundled with Nim)

## Running the tests

The full matrix covers refc + orc across `std/unittest` and `unittest2`
backends, plus a standalone osproc cell. From the project root:

```bash
nimble test
```

For quick iteration during development, one cell is usually enough:

```bash
nimble test_fast
```

The chronos async backend is opt-in because `chronos` is not in
`requires` (it's a sibling to `std/asyncdispatch`, selected per-project
by the consumer). To include the chronos cell locally:

```bash
TRIPWIRE_TEST_CHRONOS=1 nimble test
```

## Code layout

- `src/tripwire/` — core, plugins, integrations.
- `docs/plugin-authoring.md` — Plugin Authoring Rules. Required
  reading for plugin contributions.
- `docs/quickstart.md` — install, activate, first test, firewall API.
- `docs/roadmap-v0.3.md` — what v0 deliberately does not ship and
  where it is headed in v0.3.
- `tests/` — one `test_*.nim` per module, all aggregated by
  `tests/all_tests.nim`.

## Commit style

Conventional Commits. Scope in parens where it helps. Examples from the
current history:

```
feat(audit_ffi): scoped FFI pragma scan (Defense 2 Part 3)
fix(plugins/httpclient): resolve Future ambiguity under chronos
docs: correct design doc mechanism claims
chore: update author attribution
test(h7): full matrix green
```

## Pull requests

For anything non-trivial (new plugin, defect hierarchy changes, macro
surgery, FFI scope expansion), open an issue first so we can talk
through the approach. Small fixes and docs PRs are welcome without
prior discussion.

The matrix must stay green. Run `nimble test` before pushing.

## Code of conduct

Be respectful. Focus on the work.

## Alpha-quality caveat

The API may change before v0.2. Breaking changes are documented in
`CHANGELOG.md`.
