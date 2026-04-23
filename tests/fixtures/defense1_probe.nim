## Compile-fail fixture for Defense 1 (Task G2).
##
## The test harness in `tests/test_defenses.nim` runs `nim check` on
## this file under two flag combinations:
##
##   1. No defines: must fail with the {.error.} in tripwire.nim pointing
##      the user at `--define:tripwireActive` and the auto-import.
##   2. `-d:tripwireAllowInactive`: must compile clean (escape hatch for
##      tooling that wants to reference tripwire without activation).
##
## The probe body is otherwise trivial; the compile-time guard fires
## before any code runs.
import tripwire
echo "this should never run when tripwire is not activated"
