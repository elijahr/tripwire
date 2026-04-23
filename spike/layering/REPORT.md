# Spike report: TRM plugin layering in nimfoot

Environment: Nim 2.2.6, macOS (Darwin 25.4.0). All artifacts under
`/Users/eek/Development/nimfoot/spike/layering/`. Target procs in `targets.nim`
(low-layer `socketSend`, high-layer `httpGet` that calls `socketSend` internally).

## Q1 — Default layering behavior

**Files:** `q1_both_trms.nim`, `test_q1.nim`
**Compile:** `nim c --import:q1_both_trms --path:. test_q1.nim`
**Output:** `result: fake-response / httpRewrites: 1 / socketRewrites: 1`

With both TRMs injected, `httpGet("http://x")` is rewritten once. The
compiler's Pattern hint shows the rewrite body is expanded inline, and then
the inner `socketSend(...)` inside that expanded body is *also* pattern-matched
and rewritten. Net effect is a single count on each — not double-counting at
a single layer, but the low-layer TRM **does** fire inside the high-layer
rewrite. The original `httpGet` body's own `socketSend` call never executes
because the whole `httpGet` call was replaced. **Bigfoot-style "fire-through"
is the Nim default.**

## Q2 — Suppression via noRewrite

Three variants tried:

| Variant | File | Syntax | socketRewrites | Suppressed? |
|---|---|---|---|---|
| a | `q2a_push_pop.nim` | `{.push noRewrite: on.} ... {.pop.}` | 1 | **No** |
| b | `q2b_call_pragma.nim` | `{.noRewrite.}: socketSend(...)` (stmt block) | **0** | **Yes** |
| c | `q2c_bind.nim` | `bind socketSend` in template | 1 | **No** |

Only the **statement-block pragma** form `{.noRewrite.}: <call>` works. The
`push/pop` form compiles but is silently ignored by the TRM matcher (the
compiler still emits the pattern-expansion Hint for the inner call). `bind`
only controls symbol resolution, not TRM pattern matching. Nim's TRM docs
mention `{.noRewrite.}` as a per-expression override and this spike confirms
that is the only working form in 2.2.6.

## Q3 — Runtime selective layering

**Files:** `q3_runtime_flag.nim`, `test_q3.nim`
**Compile:** `nim c --import:q3_runtime_flag --path:. test_q3.nim`
**Output (flag true):** `fake-response`, httpRewrites 1
**Output (flag false):** `real-response`, httpRewrites 1 (unchanged)

Works, but requires a specific shape. The TRM match happens at compile time;
once matched, the original call site is gone. The "graceful no-op" pattern
therefore requires the rewrite body itself to contain an escape:

```nim
template rewriteHttpGet*{httpGet(url)}(url: string): string =
  if httpInterceptEnabled:
    inc(httpRewrites); "fake-response"
  else:
    {.noRewrite.}:
      httpGet(url)   # calls the real proc; not re-matched
```

The `{.noRewrite.}:` block is load-bearing — it stops the TRM from re-matching
the `httpGet(url)` the rewrite itself emits.

**Naive fallthrough failure mode (`q3b`):** without `{.noRewrite.}:`, the
compiler applies the rewrite to its own output repeatedly. Nim has an
internal TRM fixpoint-iteration cap (~26 iterations observed via repeated
Pattern hints), and after exceeding it, the final `httpGet(url)` is emitted
literally. Runtime behavior happens to be correct (returns "real-response"
when flag is false) but this is accidental, produces compile-time warning
spam, and is not a defensible pattern.

**Conclusion:** runtime-gated plugins are feasible, but every plugin must
wrap its "fallthrough" call in `{.noRewrite.}:`.

## Q4 — Cross-module layering

**Files:** `nimfoot_layering_socket.nim`, `nimfoot_layering_http.nim`,
`targets.nim`, `test_q4.nim`
**Compile:** `nim c --import:nimfoot_layering_socket --import:nimfoot_layering_http --path:. test_q4.nim`
**Output:** `result: fake-response / httpRewrites: 1 / socketRewrites: 1`

Identical to Q1. Separating the two TRMs into distinct modules and injecting
each via its own `--import:` flag reproduces exactly Q1's behavior. This
confirms the nimfoot plugin model scales to multi-module composition: each
plugin is a standalone module with its own counters, both get injected
everywhere, and both fire as Q1 describes. Unused-import warnings appear for
each injected module (cosmetic — silenceable with `{.used.}` or compiler
flags).

## Recommendation: composition model for nimfoot

**Ship fire-through as the default, with per-plugin `{.noRewrite.}:` as the
escape hatch.** Three reasons:

1. **Matches bigfoot's defense-in-depth.** If a user imports both `httpx`
   and `socket` plugins, they presumably want both layers observable in
   their assertions. The Q1/Q4 default gives that for free.
2. **Auto-suppression is unsafe.** An implicit "outer rewrite silences all
   inner rewrites" would require wrapping every rewrite body in an invisible
   `{.noRewrite.}:` block. Users authoring high-layer plugins would lose the
   ability to *deliberately* exercise low-layer interceptors (e.g. to count
   socket writes even when using the httpclient mock).
3. **`{.noRewrite.}:` is a reliable, well-scoped primitive.** Plugin
   authors who want "I handle this entirely, don't re-intercept" can wrap
   their inner calls; those who want fire-through do nothing.

Concrete guidance for the nimfoot plugin authoring doc:

- Default: write rewrite bodies normally. Assume inner calls *may* be
  rewritten by lower-layer plugins the user has also enabled.
- If a rewrite explicitly wants to bypass lower layers, wrap the inner
  call: `{.noRewrite.}: socketSend(...)`.
- If a rewrite wants runtime on/off, use the Q3 pattern with a module-level
  `{.global.}` bool and an `else: {.noRewrite.}: origProc(args)` branch.
- **Forbid** `{.push noRewrite: on.}` / `bind` — document that they look
  like they should work but don't (this spike burned time on that).

Plugin layering is configurable per call site by the plugin author, which is
the correct locus of control: the plugin knows its own semantics better than
a framework-level toggle could.
