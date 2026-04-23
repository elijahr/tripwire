# Spike #2 — TRM rewrite cap per hloBody

## Finding

Nim 2.2.6's term-rewriting-macro engine silently stops rewriting past
**~19 TRMs in a single flat hloBody** (module top-level OR proc body).
No error, no warning. The call that should have been rewritten falls
through to the real proc; for a mocking framework this means network
I/O escapes and the test "passes" with a stale assertion.

## Evidence

The `scan_N.nim` fixtures in this directory declare N TRMs and then
invoke them from a single call site, emitting a marker string per
successful rewrite. The compiled binary's stdout shows which TRMs
actually fired:

| N   | binary     | behaviour                                     |
|-----|------------|-----------------------------------------------|
| 10  | `scan_10`  | All 10 TRMs fire.                             |
| 15  | `scan_15`  | All 15 fire.                                  |
| 18  | `scan_18`  | All 18 fire.                                  |
| 19  | `scan_19`  | All 19 fire.                                  |
| 20  | `scan_20`  | First ~19 fire; #20 silently dropped.         |
| 25  | `scan_25`  | Cap at ~19; #20–25 silently dropped.          |
| 50  | `scan_50`  | Cap at ~19.                                   |
| 75  | `scan_75`  | Cap at ~19.                                   |
| 100 | `scan_100` | Cap at ~19.                                   |

Binary compiled with Nim 2.2.6 on macOS 14 arm64. Sources and binaries
are checked in; re-run by `nim c -r scan_N.nim` from this directory.

The cap is on the **hloBody**, not on the module — this was confirmed
by splitting 20 TRMs across two procs (10 each) and observing that
both procs rewrite fully.

## Threshold rationale

nimfoot enforces a hard compile-time cap of **15** rewrites per
compilation unit (see `src/nimfoot/cap_counter.nim`). Rationale:

- Conservative safety margin below the empirical ~19: leaves room for
  Nim internal changes that might lower the silent threshold.
- Typical test modules invoke 1–3 distinct TRMs per hloBody in
  practice, so a ceiling of 15 accommodates ~5 tests per module
  before forcing a split into helper modules.
- A false positive produces a **loud compile-time `{.error.}`** with
  a message pointing the user at `sandbox:` sub-blocks — strictly
  better than the silent drop at ~19.

## Implementation

See `src/nimfoot/cap_counter.nim`. The `nimfootCountRewrite` macro
uses a `{.compileTime.}` counter. Every plugin TRM body (via
`nimfootInterceptBody` or `nimfootPluginIntercept`) calls it first,
so the counter increments on every *expansion*, not on every *TRM
declaration*. This means defined-but-never-called TRMs do NOT count
— users only pay the cap on TRMs they actually trigger.

Past the cap, `macros.error` aborts compilation with:

```
nimfoot: more than 15 TRM rewrites in a single compilation unit.
Nim's rewrite engine silently drops rewrites past ~19. Split the
test with `sandbox:` sub-blocks or refactor into smaller helpers.
```

The error fires from inside the macro (not from a `when`-guarded
`{.error.}` in a `static:` block) because Nim's `when` evaluates
during sem-check before `{.compileTime.}` mutations become visible
to the branch predictor, causing silent non-firing. Using
`macros.error` from a macro bypasses that phase-ordering pitfall.

## Test coverage

- `tests/test_cap_counter.nim` — the compile-fail probe (16 rewrites
  trigger `{.error.}`) and the 15-rewrite compile-clean probe.
- `tests/fixtures/cap_overflow.nim` — the 16-rewrite fixture the
  compile-fail probe shells out to via `nim check`.
- `tests/test_defenses.nim` (H3) — a message-shape regression check
  on the exported `NimfootCapThreshold` constant.
