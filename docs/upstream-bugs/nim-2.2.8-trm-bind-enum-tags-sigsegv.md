# Nim 2.2.8: TRM `{.dirty.}` template `bind`-ing enum tag identifiers SIGSEGVs the rewriter

## Environment

- Nim Compiler Version 2.2.8 (MacOSX arm64; reproducer expected to be platform-independent)
- Platform: Darwin 25.4.0 (kernel 25.4.0, xnu-12377.101.15~1)
- Build flag: `--mm:refc`
- Test runner harness: `--define:tripwireActive --import:tripwire/auto -r tests/all_tests.nim`

## Symptom

A `{.dirty.}` template that participates in TRM (term-rewriting macros) and
whose body switches on values returned from a free proc using a `case`
statement compiles cleanly in isolation. As soon as the template's `bind`
clause includes the enum's tag identifiers (so the case branches resolve
unqualified), the compiler segfaults during heavy aggregate compilation
(many TRM expansion sites in one compilation unit).

The crash is not a Nim error message — it is a raw process SIGSEGV during
sem/typing of a TRM expansion site. No stacktrace is produced.

## Reproducer (reduced from tripwire)

The bug is triggered by binding enum tag identifiers (`osdRaise`,
`osdRaiseNoPassthrough`, `osdPassthrough`) into a `{.dirty.}` template
that is also a TRM target. A minimal reproducer that exercises the same
code path requires:

1. A `{.dirty.}` template that is registered as a TRM rewrite target
   (via the standard `pattern -> body` form).
2. The template body must contain a `case` statement on a value of
   enum type returned from a free proc.
3. The template's `bind` clause must list the enum's tag identifiers.
4. A separate compilation unit that imports the template and expands
   it many times via TRM rewriting (in the tripwire reproducer, the
   `httpclient.requestAsyncTRM` site).

The smallest standalone Nim program that exhibits the SIGSEGV is
roughly:

```nim
# bug.nim — sketch; requires further reduction by upstream filer
import std/macros

type
  Disposition = enum
    dispRaise, dispRaisePolicy, dispPassthrough

proc decide(): Disposition = dispRaise

template work*(spyBody: untyped): untyped {.dirty.} =
  bind dispRaise, dispRaisePolicy, dispPassthrough
  case decide()
  of dispRaise: raise newException(Defect, "")
  of dispRaisePolicy: raise newException(Defect, "")
  of dispPassthrough: spyBody

# A TRM-style template wrapping `work` and rewriting many call sites
# in a separate compilation unit reliably crashes Nim 2.2.8 sem.
```

The tripwire-internal repro is: revert the bool-form predicate
`outsideSandboxShouldPassthrough` to its bisect-rejected enum form
(`OutsideSandboxDisposition` with `osdRaise` / `osdRaiseNoPassthrough` /
`osdPassthrough`), bind those tags into
`tripwireInterceptBody`'s `bind` clause, and re-build Cell 1
(`nim c --mm:refc --define:tripwireActive --import:tripwire/auto -r tests/all_tests.nim`).

## Compile command

```
nim c --mm:refc --define:tripwireActive --import:tripwire/auto -r tests/all_tests.nim
```

## Expected behavior

The compiler succeeds — `bind`-ing enum tag identifiers into a
`{.dirty.}` template's `bind` clause is documented as supported.

## Actual behavior

```
SIGSEGV (no stacktrace)
```

The crash is during the aggregate compilation of `tests/all_tests.nim`
when the TRM rewriter is expanding many `requestAsyncTRM` (httpclient
plugin) sites; reverting the enum-form change makes the crash go away.

## Workaround applied in tripwire

Replace the enum-disposition shape with a `bool` predicate
(`outsideSandboxShouldPassthrough`) that **raises** on the rejection
branches and **returns true/false** on the passthrough branches. The
TRM body switches on the bool via short-circuit `and` rather than a
`case` over enum tags, so no enum tag identifier needs to appear in
the `bind` clause.

See `src/tripwire/intercept.nim:outsideSandboxShouldPassthrough`
and the `tripwireInterceptBody` `bind` clause for the applied shape.

## Notes for upstream filer

- The crash is NOT a Nim ICE with a `vmgen.nim` or `sem*.nim` line —
  it is a SIGSEGV on the compiler process, suggesting an unguarded
  pointer deref inside the TRM rewriter when a `bind`-ed identifier
  is an enum tag.
- Reduction is non-trivial because TRM expansion only triggers under
  specific aggregate compilation conditions; a single-file repro
  often does not crash, while a cross-module TRM expansion site does.
- Possibly related to the way `bind` interacts with `nkSym` resolution
  for typedesc-of-enum members during rewriter pattern matching.
