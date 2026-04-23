## Compile-fail fixture for Defense 3 (Task D2).
##
## Calls `tripwireCountRewrite` 16 times at module scope. The 16th invocation
## MUST emit a `{.error.}` at compile time. The test harness in
## `tests/test_cap_counter.nim` runs `nim check` on this file and asserts
## the compiler exits non-zero with the cap-threshold message.
import tripwire/cap_counter

tripwireCountRewrite()   # 1
tripwireCountRewrite()   # 2
tripwireCountRewrite()   # 3
tripwireCountRewrite()   # 4
tripwireCountRewrite()   # 5
tripwireCountRewrite()   # 6
tripwireCountRewrite()   # 7
tripwireCountRewrite()   # 8
tripwireCountRewrite()   # 9
tripwireCountRewrite()   # 10
tripwireCountRewrite()   # 11
tripwireCountRewrite()   # 12
tripwireCountRewrite()   # 13
tripwireCountRewrite()   # 14
tripwireCountRewrite()   # 15 — last one allowed
tripwireCountRewrite()   # 16 — must error
