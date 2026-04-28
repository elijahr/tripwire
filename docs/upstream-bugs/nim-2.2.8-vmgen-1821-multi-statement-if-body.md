# Nim 2.2.8: vmgen ICE 1821,23 on multi-statement `if isNil:` body inside TRM under refc + unittest2 `failingOnExceptions`

## Environment

- Nim Compiler Version 2.2.8 (MacOSX arm64)
- Platform: Darwin 25.4.0 (kernel 25.4.0, xnu-12377.101.15~1)
- Build flags: `--mm:refc --define:tripwireActive --define:tripwireUnittest2`
- Triggering harness: unittest2 0.2.5
  (`pkgs2/unittest2-0.2.5-02bb3751ba9ddc3c17bfd89f2e41cb6bfb8fc0c9`)
  via `import unittest2`'s `failingOnExceptions` template wrapper.

## Symptom

```
Error: internal error: /home/runner/work/nightlies/nightlies/nim/compiler/vmgen.nim(1821, 23)
No stack traceback available
```

The ICE fires during semantic analysis of a TRM expansion site that is
itself wrapped by unittest2's `failingOnExceptions` template, when the
TRM body's `if nfVerifier.isNil:` branch contains more than one
statement.

## Reduced symptom

The combinator template body schema that triggers the ICE:

```nim
template tripwireInterceptBody*(plugin: Plugin, procName: string,
                               fingerprint: string,
                               responseType: typedesc,
                               spyBody: untyped): untyped {.dirty.} =
  let nfVerifier {.inject.} = currentVerifier()
  if nfVerifier.isNil:
    # TWO statements here trips vmgen 1821,23 in Cell 3.
    discard outsideSandboxShouldPassthrough(plugin, procName, instInfo())
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  ...
```

Other multi-statement shapes that were bisected and confirmed to crash:

- Nested `if`: `if ...: result = spyBody; return` followed by `raise ...`.
- `when typeof(spyBody) is void:` split inside the if-isNil body.
- A `block:` wrapper around the multi-statement body.
- An intermediate `let nfOsCallsite = ...` followed by a single `raise`.
- A plain `result = spyBody; return` inside the if-isNil body.

The ONLY shape that survives is a single statement in the `if isNil:`
body (typically `raise newLeakedInteractionDefect(...)`).

## Triggering site (in tripwire)

`tests/test_self_three_guarantees.nim`'s

```nim
expect TripwireDefect:
  ...
  waitFor c.get(...)
```

block. The `expect` macro is from unittest2; its expansion wraps the
body in `failingOnExceptions` which contains a `try`/`except` whose
`except` clause re-raises after pattern-matching the exception type.
The ICE fires inside vmgen's register-slot tracking for that wrapping.

## Reproducer

A minimal standalone reproducer requires:

1. A `{.dirty.}` template combinator with a `typedesc` parameter
   that participates in TRM rewriting.
2. A consumer that calls the TRM at least once inside an
   `expect ...:` block from `unittest2`.
3. Build with `--mm:refc --define:tripwireUnittest2`.

The tripwire-internal repro is: extend the `if nfVerifier.isNil:` body
in `src/tripwire/intercept.nim` (or `src/tripwire/plugins/plugin_intercept.nim`)
with any additional statement and rebuild Cell 3
(`nim c --mm:refc --define:tripwireActive --define:tripwireUnittest2 --import:tripwire/auto tests/all_tests.nim`).

A standalone reduction attempt below is structurally faithful but has
NOT been confirmed to ICE in isolation — the crash is sensitive to
aggregate-compilation conditions and may require additional surrounding
TRM expansion sites:

```nim
# bug.nim — STRUCTURAL SKETCH. Requires further reduction by upstream filer.
import std/options
import unittest2

type
  Verifier = ref object
    active: bool
  MyDefect = object of Defect

var verifierStack: seq[Verifier]
proc currentVerifier(): Verifier =
  if verifierStack.len > 0: verifierStack[^1] else: nil

template work*(plugin: string, respType: typedesc, spyBody: untyped): untyped {.dirty.} =
  let v = currentVerifier()
  if v.isNil:
    discard plugin.len  # second statement
    raise newException(MyDefect, "leaked")
  spyBody

proc fetch(): int =
  work("plugin", int):
    42

suite "repro":
  test "ICE":
    expect MyDefect:
      discard fetch()
```

## Compile command

```
nim c --mm:refc --define:tripwireActive --define:tripwireUnittest2 --import:tripwire/auto tests/all_tests.nim
```

(or, for a single-test repro, see the standalone sketch above.)

## Expected behavior

Compiles cleanly. The semantics of multiple statements inside an `if`
body are well-defined and supported.

## Actual behavior

```
Error: internal error: /home/runner/work/nightlies/nightlies/nim/compiler/vmgen.nim(1821, 23)
No stack traceback available
To create a stacktrace, rerun compilation with './koch temp c <file>'
```

## Workaround applied in tripwire

Hoist the multi-statement work OUT of the `if nfVerifier.isNil:` branch,
keeping that branch a single `raise`. The decision-bearing statements
move into a separately-evaluated `let nfOutsideHandled = nfVerifier.isNil and ...`
binding (using short-circuit `and` to avoid invoking the predicate when
a verifier is in scope), and a structurally distinct
`if not nfOutsideHandled: ... else: spyBody` block dispatches between
the verifier-path and the guard='warn' passthrough path. The
`else: spyBody` form is load-bearing — `result = spyBody; return` would
fail at expression-context call sites such as `discard c.request(...)`
where the consumer has no `result` variable.

See `src/tripwire/intercept.nim:tripwireInterceptBody` and
`src/tripwire/plugins/plugin_intercept.nim:tripwirePluginIntercept`
for the applied shapes.

## Notes for upstream filer

- The line/column `vmgen.nim(1821, 23)` references the upstream nightly's
  `vmgen.nim`; the corresponding source location may differ in tagged
  releases. The error path is the register-slot tracking inside vmgen
  during semcheck of an expression that cannot be VM-evaluated (the
  unittest2 `failingOnExceptions` wrapper attempts compile-time
  evaluation of the wrapped body's exception-effect graph).
- The bug appears to depend on the **interaction** of: (a) refc memory
  manager, (b) unittest2's `failingOnExceptions` wrapping, (c) a
  `{.dirty.}` template participating in TRM, and (d) more than one
  statement in a guarded raise branch. Removing any one of (a)/(b)/(c)
  makes the crash go away.
- Possibly related upstream issues to search for:
  `vmgen.nim 1821`, `failingOnExceptions ICE`,
  `dirty template TRM internal error`.
