# Spy Mode Spike — Findings

Nim: 2.2.6 at `/Users/eek/.local/share/mise/installs/nim/2.2.6/bin/nim`
All source + binaries live under `/Users/eek/Development/nimfoot/spike/spy/`.
Compile invocation pattern:
`nim c --hints:off --warnings:on --import:<trm_module> <test>.nim`

## Q1 — Does `{.noRewrite.}` suppress TRM matching?

Three syntactic variants were tried:

### Q1a — `target(a, b) {.noRewrite.}` (pragma on call expression)
File: `nimfoot_spy_q1a.nim` + `test_q1a_direct.nim`
Compile error:
```
test_q1a_direct.nim(4, 16) Error: invalid pragma: target(2, 3) {.noRewrite.}
```
**Verdict: does not parse.** Nim does not accept a pragma suffix on a call expression.

### Q1b — `{.noRewrite.}:` pragma block (WORKS)
File: `nimfoot_spy_q1b.nim`:
```nim
template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  {.noRewrite.}:
    target(a, b)
```
Results:
- `test_q1b_direct.nim`: single call -> `r1=5 count=1` — correct spy behavior.
- `test_q1b_obs.nim` (observable body `target(a, b) + 1000`): `r1=1005 count=1` — inner call NOT re-matched.
- `test_q1b_multi.nim`: three call sites in three procs -> `a=5 b=30 c=14 count=3` — one match per site.
- `test_q1b_inject.nim`: TRM injected via `--import:` into unmodified `thirdparty_spy.nim` -> `a=11 b=15 count=3` — works through injection.

**Verdict: `{.noRewrite.}:` pragma block works reliably in 2.2.6.** No warnings, no recursion, no cap trip.

### Q1c — `{.push noRewrite.}` / `{.pop.}` (BROKEN)
File: `nimfoot_spy_q1c.nim` + `test_q1c.nim`
Result: `r1=5 count=23` — the rewrite loop ran 23 times before Nim's internal cap halted it. So `{.push noRewrite.}` is ignored by the term-rewriting engine. Only the pragma-block form is recognized.

## Q2 — Capture-the-original via function pointer

### Q2a — `let origTarget* = target` before TRM definition (WORKS)
File: `nimfoot_spy_q2a.nim`:
```nim
let origTarget* = target
var rewriteCount* {.global.} = 0
template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  origTarget(a, b)
```
Results:
- `test_q2a.nim` (single): `r1=5 count=1`.
- `test_q2a_multi.nim` (three sites): `a=5 b=30 c=14 count=3`.
- `test_q2a_inject.nim` (via `--import:` into `thirdparty_spy`): `a=11 b=15 count=3`.

The TRM pattern `target(a, b)` only fires on direct calls to the `target` symbol. A call through a `proc` variable (`origTarget(a, b)`) is not syntactically `target(a, b)` and does not match. `let origTarget = target` is legal because procs are first-class.

### Q2b — anonymous-proc wrapper (WORKS)
File: `nimfoot_spy_q2b.nim`:
```nim
let origTarget* = proc(a, b: int): int = target(a, b)
```
Results: `test_q2b.nim` -> `r1=5 r2=30 count=2`.
The `target(a, b)` inside the lambda body is elaborated BEFORE the TRM is registered in the user-compilation unit, so the lambda captures the raw proc symbol without rewriting. Subsequent calls through `origTarget` bypass the TRM pattern.

## Q3 — Distinct-name forwarding / `bind` + `let`

### Q3a — `bind target; let realFn = target; realFn(a, b)` (WORKS)
File: `nimfoot_spy_q3a.nim`:
```nim
template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  bind target
  let realFn = target
  realFn(a, b)
```
Results:
- `test_q3a.nim`: `r1=5 r2=30 count=2`.
- `test_q3a_inject.nim`: `a=11 b=15 count=3`.
The `bind target` is optional here (single-target ambiguity only), but harmless. The key mechanism is the same as Q2: the `realFn(a, b)` call is a proc-var call, not a direct symbol match.

### Q3b — `let realFn {.noRewrite.} = target` (REJECTED)
File: `nimfoot_spy_q3b.nim`.
Compile error:
```
nimfoot_spy_q3b.nim(9, 16) Error: invalid pragma: noRewrite
```
`noRewrite` is not a pragma valid on a variable declaration. It only exists as a statement-block pragma.

## Recommendation

Use **Q1b (`{.noRewrite.}:` pragma block)** for nimfoot's spy mode.

Rationale:
1. It is the most direct expression of intent — "don't rewrite this particular call" — and is
   documented Nim semantics (issue #20115 fix landed for exactly this form).
2. No runtime cost: the real `target` is called statically, no proc-var indirection.
3. Preserves overload resolution, default args, generic-sig inference — whatever the compiler
   does for a direct call also works here. Q2a/Q3a lose this by going through a typed proc var
   (procedural type has to be expressible, which breaks for generic / default-arg / varargs procs).
4. Verified working under all four scenarios: single, multi-site, observable, and `--import:`
   injection into third-party modules.

Confidence: **high** that this pattern is reliable for concrete non-generic proc signatures
in Nim 2.2.6. I observed zero recursion, zero warnings, and the cap never tripped across ten
separate compile+run cycles.

Fallbacks if `{.noRewrite.}:` ever misbehaves on a specific signature:
- Q2a (`let origTarget = target`) as long as the proc has an expressible proc type.
- Q3a (`let realFn = target` inside the template body) for the same reason, with the advantage
  that the capture is per-expansion rather than module-global.

Neither fallback is suitable for generic / varargs / default-arg procs. For those, the spy
mechanism will have to fall back to `{.noRewrite.}:` regardless — so standardize on Q1b.

## Files under /Users/eek/Development/nimfoot/spike/spy/
- `common_spy.nim` — shared `target*` proc.
- `thirdparty_spy.nim` — unmodified-library simulator.
- `nimfoot_spy_q1a.nim`, `test_q1a_direct.nim` — pragma-on-call (compile error).
- `nimfoot_spy_q1b.nim`, `nimfoot_spy_q1b_obs.nim`, `test_q1b_*.nim` — pragma-block (PASS).
- `nimfoot_spy_q1c.nim`, `test_q1c.nim` — push/pop (BROKEN, cap trip).
- `nimfoot_spy_q2a.nim`, `test_q2a*.nim` — let-capture proc symbol (PASS).
- `nimfoot_spy_q2b.nim`, `test_q2b.nim` — anon-proc wrapper (PASS).
- `nimfoot_spy_q3a.nim`, `test_q3a*.nim` — bind + let inside template (PASS).
- `nimfoot_spy_q3b.nim`, `test_q3b.nim` — let-with-noRewrite-pragma (REJECTED).
