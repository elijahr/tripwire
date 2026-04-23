## tripwire — test mocking with three-guarantee enforcement.
##
## This is the public facade. Consumers put ONE import in their test
## modules:
##
## ```nim
## import tripwire
## ```
##
## and activate the framework globally via their test `config.nims`:
##
## ```nim
## --import:"tripwire/auto"
## --define:"tripwireActive"
## --warning:UnusedImport:off
## ```
##
## The `--import:"tripwire/auto"` flag injects the umbrella module
## (which imports every built-in plugin) into every test translation
## unit, wiring plugin TRMs into scope globally. `-d:tripwireActive`
## gates that injection and also tells this facade the user really
## did activate tripwire.
##
## Without activation, importing this facade is almost certainly a
## mistake (plugin TRMs are not in scope; interactions would silently
## call through to the real implementations and the three-guarantee
## invariants cannot hold). Defense 1 below fails the build loudly
## in that case. Tooling that legitimately needs to reference tripwire
## symbols without wiring activation can opt out via
## `-d:tripwireAllowInactive`.
##
## See design doc §5 (activation model) and §10 Defense 1.

# ---- Defense 1 — activation guard --------------------------------------
# If the consumer imports this facade but neither activation define nor
# the explicit escape hatch is set, emit a clear compile-time error.
# Keeping the whole {.error.} string on one flow branch (no string
# interpolation) so the message in the compiler output is stable and
# grep-testable from test_defenses.nim.
when not defined(tripwireActive) and not defined(tripwireAllowInactive):
  {.error: "tripwire was imported but not activated. " &
    "Add `--import:\"tripwire/auto\"` and `--define:\"tripwireActive\"` " &
    "to your test config.nims, or `--define:\"tripwireAllowInactive\"` " &
    "to suppress this error.".}

# ---- Public API surface -------------------------------------------------
# One `import ... export ...` per core module. The facade does NOT
# import the plugin modules: those are the responsibility of `auto.nim`
# (activated via `--import:"tripwire/auto"`). Re-exporting plugins here
# would reintroduce the "plugin TRM body needs popMatchingMock bound
# at expansion site" failure mode in TUs that have `import tripwire`
# but do not have `--import:tripwire/auto` active (e.g., a user who
# forgot the auto-import but set `-d:tripwireAllowInactive`).

import tripwire/types
import tripwire/errors
import tripwire/timeline
import tripwire/sandbox
import tripwire/verify
import tripwire/intercept
import tripwire/macros as nfmacros
import tripwire/config
import tripwire/futures
import tripwire/integration_unittest

export types, errors, timeline, sandbox, verify, intercept, nfmacros,
       config, futures, integration_unittest

# ---- Defense 2 Part 3 — FFI audit hook ---------------------------------
# Opt-in transitive FFI scan. v0 ships a stub that emits a hint; real
# pragma scanning lands in v0.1. Kept outside the main export list so
# that consumers who set `-d:tripwireAuditFFI` see the hint but don't
# bring a no-op symbol into their namespace.
when defined(tripwireAuditFFI):
  import ./tripwire/audit_ffi
