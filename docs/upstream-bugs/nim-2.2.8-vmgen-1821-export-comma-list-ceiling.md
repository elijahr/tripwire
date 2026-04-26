# Nim 2.2.8: vmgen ICE 1821,23 when an umbrella module exports more than nine `errors.X` symbols under refc + unittest2

## Environment

- Nim Compiler Version 2.2.8 (MacOSX arm64)
- Platform: Darwin 25.4.0 (kernel 25.4.0, xnu-12377.101.15~1)
- Build flags: `--mm:refc --define:tripwireActive --define:tripwireUnittest2`
- Triggering harness: unittest2 0.2.5 via `import unittest2`
  (`failingOnExceptions` template wrapper around the test body).

## Symptom

Adding a tenth (or further) `errors.X` re-export to
`src/tripwire/auto_internal_exports.nim` trips:

```
Error: internal error: /home/runner/work/nightlies/nightlies/nim/compiler/vmgen.nim(1821, 23)
No stack traceback available
```

The crash fires at `tests/test_self_three_guarantees.nim`'s
`expect TripwireDefect: ... waitFor c.get(...)` block — the same vmgen
register-slot path as
`docs/upstream-bugs/nim-2.2.8-vmgen-1821-multi-statement-if-body.md`,
but triggered by a different surface change.

## Reduced symptom

The umbrella module currently exports nine error symbols on a single
comma-separated `export` statement:

```nim
# src/tripwire/auto_internal_exports.nim
export errors.TripwireDefect,
       errors.LeakedInteractionDefect,
       errors.PostTestInteractionDefect,
       errors.UnmockedInteractionDefect,
       errors.UnassertedInteractionsDefect,
       errors.UnusedMocksDefect,
       errors.newLeakedInteractionDefect,
       errors.newPostTestInteractionDefect,
       errors.newUnmockedInteractionDefect
```

Adding ANY further `errors.Y` symbol — whether folded into the
existing comma-list:

```nim
export errors.TripwireDefect, ..., errors.newUnmockedInteractionDefect,
       errors.OutsideSandboxNoPassthroughDefect    # <-- crashes
```

OR placed on a fresh `export errors.Y` statement:

```nim
export errors.TripwireDefect, ..., errors.newUnmockedInteractionDefect
export errors.OutsideSandboxNoPassthroughDefect    # <-- also crashes
```

OR split across two roughly-equal-length statements:

```nim
export errors.TripwireDefect, errors.LeakedInteractionDefect,
       errors.PostTestInteractionDefect, errors.UnmockedInteractionDefect,
       errors.UnassertedInteractionsDefect, errors.UnusedMocksDefect
export errors.newLeakedInteractionDefect,
       errors.newPostTestInteractionDefect,
       errors.newUnmockedInteractionDefect,
       errors.OutsideSandboxNoPassthroughDefect,
       errors.newOutsideSandboxNoPassthroughDefect    # <-- still crashes
```

…all three forms reproduce vmgen 1821,23 in Cell 3.

The crash count appears to depend on the **total number** of `errors.X`
re-exports in the umbrella module (nine works, ten or more crashes),
not on the number of statements they are spread across or on the symbol
identities themselves.

## Reproducer

The bug's surface is a `tripwire/auto`-shaped umbrella that re-exports
many symbols from a `tripwire/errors`-shaped module containing many
defect types and constructor procs, where the consumer triggers a
TRM expansion site inside a unittest2 `expect`. A standalone reduction
that does not require the rest of tripwire is sketched below; it has
NOT been confirmed to ICE in isolation and may need additional
TRM-shaped scaffolding:

```nim
# errors_lib.nim
type
  TripwireDefect* = object of Defect
  LeakedInteractionDefect* = object of TripwireDefect
  PostTestInteractionDefect* = object of TripwireDefect
  UnmockedInteractionDefect* = object of TripwireDefect
  UnassertedInteractionsDefect* = object of TripwireDefect
  UnusedMocksDefect* = object of TripwireDefect
  OutsideSandboxNoPassthroughDefect* = object of TripwireDefect

proc newLeakedInteractionDefect*(): ref LeakedInteractionDefect = nil
proc newPostTestInteractionDefect*(): ref PostTestInteractionDefect = nil
proc newUnmockedInteractionDefect*(): ref UnmockedInteractionDefect = nil
proc newOutsideSandboxNoPassthroughDefect*(): ref OutsideSandboxNoPassthroughDefect = nil

# auto.nim — umbrella
import errors_lib
export errors_lib.TripwireDefect,
       errors_lib.LeakedInteractionDefect,
       errors_lib.PostTestInteractionDefect,
       errors_lib.UnmockedInteractionDefect,
       errors_lib.UnassertedInteractionsDefect,
       errors_lib.UnusedMocksDefect,
       errors_lib.newLeakedInteractionDefect,
       errors_lib.newPostTestInteractionDefect,
       errors_lib.newUnmockedInteractionDefect,
       errors_lib.OutsideSandboxNoPassthroughDefect    # <-- 10th symbol
```

Then a consumer with a TRM combinator + unittest2 `expect` over an
async `waitFor` site, compiled with `--mm:refc --define:tripwireUnittest2`.

The tripwire-internal repro is: append any `errors.Y` to the umbrella's
`export errors....` block in
`src/tripwire/auto_internal_exports.nim` and rebuild Cell 3
(`nim c --mm:refc --define:tripwireActive --define:tripwireUnittest2 --import:tripwire/auto tests/all_tests.nim`).

## Compile command

```
nim c --mm:refc --define:tripwireActive --define:tripwireUnittest2 --import:tripwire/auto tests/all_tests.nim
```

## Expected behavior

Compiles cleanly. Re-exporting additional symbols through an umbrella
module is a standard and well-supported Nim pattern.

## Actual behavior

```
Error: internal error: /home/runner/work/nightlies/nightlies/nim/compiler/vmgen.nim(1821, 23)
No stack traceback available
```

## Workaround applied in tripwire

Cap the umbrella module's `errors.X` re-exports at nine. Symbols past
that cap (currently `OutsideSandboxNoPassthroughDefect` and
`newOutsideSandboxNoPassthroughDefect`) remain reachable via direct
`import tripwire/errors`. The umbrella's docstring and the export-site
comment block call the cap out as load-bearing.

See `src/tripwire/auto_internal_exports.nim` for the applied workaround.

## Notes for upstream filer

- Same `vmgen.nim(1821, 23)` location as the multi-statement-if-body
  bug; appears to be a shared register-slot tracking bug whose trigger
  surface is broader than just one TRM body shape.
- The crash count threshold (nine) is empirical and may shift between
  Nim point releases; the symptom is the relevant one to file.
- The crash occurs in semcheck of `expect TripwireDefect: ... waitFor`
  every time, regardless of which specific `errors.X` symbol pushed
  the umbrella over the cap, suggesting the trigger is the size of
  the imported scope visible at the `expect` expansion site rather
  than a particular symbol's properties.
