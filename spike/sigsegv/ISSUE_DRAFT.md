# NOT FILED — investigation concluded the bug is not reproducible

**Do not file this as-is.** The prior spike comment at
`spike/nimfoot_auto.nim:13-16` warns of a Nim 2.2.6 SIGSEGV when a term-rewriting
macro has `[T]` generic parameters on the template itself. After systematic
attempts across 8+ variant shapes, the crash **does not reproduce** on the
installed 2.2.6 (git `ab00c569`). The investigation below is preserved for
reference; an upstream issue would need a confirmed crashing input before filing.

---

### Description (for reference only)
Prior claim: in Nim 2.2.6, a term-rewriting macro (TRM) declared as
`template name*{pattern}[T](args: T): T = body` triggers a compiler SIGSEGV
during semantic analysis. **This claim is not supported by the current compiler
binary.**

### Repro attempted (compiles cleanly — does NOT crash)

```nim
## Literal shape from the spike's cautionary comment.
proc targetGeneric*[T](x, y: T): T = x + y

var rewriteCountGeneric* {.global.} = 0

template rewriteTargetGeneric*{targetGeneric(a, b)}[T](a, b: T): T =
  inc(rewriteCountGeneric)
  a + b + 1000

let r1 = targetGeneric(2, 3)
let r2 = targetGeneric[int](10, 20)
echo r1, " ", r2, " count=", rewriteCountGeneric
```

### Compiler invocation
```
/Users/eek/.local/share/mise/installs/nim/2.2.6/bin/nim c min_repro.nim
```

### Output (success — no SIGSEGV)
```
Hint: used config file '/Users/eek/.local/share/mise/installs/nim/2.2.6/config/nim.cfg' [Conf]
........................................................................................
min_repro.nim(14, 23) Hint: rewriteTargetGeneric(2, 3) --> '
inc(rewriteCountGeneric, 1)
1005' [Pattern]
min_repro.nim(15, 28) Hint: rewriteTargetGeneric(10, 20) --> '
inc(rewriteCountGeneric, 1)
1030' [Pattern]
Hint:  [Link]
Hint: mm: orc; threads: on; opt: none
42918 lines; 0.279s; 59.742MiB peakmem; SuccessX
```

Runtime output of the compiled binary: `1005 1030 count=2` (TRM fires at both
call sites, both rewrites execute, count increments correctly).

### Variants tried — all compile cleanly, none crash

- **Single-file, generic target + `[T]` TRM + inc(global)**: compiles, TRM
  fires, output correct.
- **Multi-module (`repro_common.nim` / `repro_trm.nim` / `repro_main.nim`),
  mirroring the `thirdparty.nim` / `nimfoot_auto.nim` / `test_*.nim` split**:
  compiles, TRM fires, output correct.
- **With `--import:repro_trm` injection** (the `nimfoot_auto` shape): compiles,
  TRM fires twice (once via explicit import, once via `--import`), output correct.
- **Generic wrapper (`proc useIt[T](x: T): T = targetGeneric(x, x)`) called
  with both `int` and `float`**: compiles, TRM fires at instantiation time.
- **Float instantiation (`targetGeneric(2.0, 3.0)`)**: compiles, TRM fires,
  rewrites to `5.0`.
- **Non-generic target + `[T]` TRM**: compiles, TRM fires.
- **Template with `[T: SomeNumber]` constraint**: compiles, TRM fires.
- **Explicit `targetGeneric[T](a, b)` in pattern**: compiles, but TRM does not
  fire (likely a matching subtlety — separate question).
- **Arity mismatch between pattern captures (2) and template params (1)**:
  compiles without error and without firing.
- **Template defined BEFORE target proc in source order (forward-reference
  shape)**: compiles, TRM fires.
- **Self-referencing body (`body = targetGeneric(a, a)`)**: compiles, TRM caps
  at 17 expansions per site (expected loop-limit behavior), no crash.
- **Object-typed argument where `+` is undefined**: compiles (because the
  sample body does not use `+`), TRM fires.

### `--patterns:off` (alias for `--trmacros:off`) behavior
With TRMs disabled the compile also succeeds (`count=0`, values `5` and `30`
rather than `1005` and `1030`, confirming the TRM is what produces the
rewrite). Note: in 2.2.6 the flag is emitted as:

```
Warning: 'patterns' is a deprecated alias for 'trmacros' [Deprecated]
```

### Environment
- Nim Compiler Version 2.2.6 [MacOSX: arm64]
- Compiled 2025-10-31
- git hash: `ab00c56904e3126ad826bb520d243513a139436a`
- Boot switches: `-d:release -d:danger`
- Binary: `/Users/eek/.local/share/mise/installs/nim/2.2.6/bin/nim`

### Recommendation
Remove (or retract) the cautionary comment at `spike/nimfoot_auto.nim:13-16`.
The generic `[T]` TRM form appears to compile and function correctly on the
current 2.2.6 release. If a crash was observed earlier it was likely on a
different compiler build, a different source shape, or has since been fixed.

Before filing anything upstream, the specific failing input must be captured
at the time of failure (error message + exact source) — the surviving evidence
in this spike is a comment without a preserved repro, which is not sufficient
to file.
