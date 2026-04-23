## Compile-fail fixture for Defense 1 (Task G2).
##
## The test harness in `tests/test_defenses.nim` runs `nim check` on
## this file under two flag combinations:
##
##   1. No defines: must fail with the {.error.} in nimfoot.nim pointing
##      the user at `--define:nimfootActive` and the auto-import.
##   2. `-d:nimfootAllowInactive`: must compile clean (escape hatch for
##      tooling that wants to reference nimfoot without activation).
##
## The probe body is otherwise trivial; the compile-time guard fires
## before any code runs.
import nimfoot
echo "this should never run when nimfoot is not activated"
