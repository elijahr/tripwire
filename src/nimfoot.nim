## nimfoot — test mocking with three-guarantee enforcement.
##
## This is the public facade. Consumers put ONE import in their test
## modules:
##
## ```nim
## import nimfoot
## ```
##
## and activate the framework globally via their test `config.nims`:
##
## ```nim
## --import:"nimfoot/auto"
## --define:"nimfootActive"
## --warning:UnusedImport:off
## ```
##
## The `--import:"nimfoot/auto"` flag injects the umbrella module
## (which imports every built-in plugin) into every test translation
## unit, wiring plugin TRMs into scope globally. `-d:nimfootActive`
## gates that injection and also tells this facade the user really
## did activate nimfoot.
##
## Without activation, importing this facade is almost certainly a
## mistake (plugin TRMs are not in scope; interactions would silently
## call through to the real implementations and the three-guarantee
## invariants cannot hold). Defense 1 below fails the build loudly
## in that case. Tooling that legitimately needs to reference nimfoot
## symbols without wiring activation can opt out via
## `-d:nimfootAllowInactive`.
##
## See design doc §5 (activation model) and §10 Defense 1.

# ---- Defense 1 — activation guard --------------------------------------
# If the consumer imports this facade but neither activation define nor
# the explicit escape hatch is set, emit a clear compile-time error.
# Keeping the whole {.error.} string on one flow branch (no string
# interpolation) so the message in the compiler output is stable and
# grep-testable from test_defenses.nim.
when not defined(nimfootActive) and not defined(nimfootAllowInactive):
  {.error: "nimfoot was imported but not activated. " &
    "Add `--import:\"nimfoot/auto\"` and `--define:\"nimfootActive\"` " &
    "to your test config.nims, or `--define:\"nimfootAllowInactive\"` " &
    "to suppress this error.".}

# ---- Public API surface -------------------------------------------------
# One `import ... export ...` per core module. The facade does NOT
# import the plugin modules: those are the responsibility of `auto.nim`
# (activated via `--import:"nimfoot/auto"`). Re-exporting plugins here
# would reintroduce the "plugin TRM body needs popMatchingMock bound
# at expansion site" failure mode in TUs that have `import nimfoot`
# but do not have `--import:nimfoot/auto` active (e.g., a user who
# forgot the auto-import but set `-d:nimfootAllowInactive`).

import nimfoot/types
import nimfoot/errors
import nimfoot/timeline
import nimfoot/sandbox
import nimfoot/verify
import nimfoot/intercept
import nimfoot/macros as nfmacros
import nimfoot/config
import nimfoot/futures
import nimfoot/integration_unittest

export types, errors, timeline, sandbox, verify, intercept, nfmacros,
       config, futures, integration_unittest
