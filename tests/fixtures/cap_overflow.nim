## Compile-fail fixture for Defense 3 (Task D2).
##
## Calls `nimfootCountRewrite` 16 times at module scope. The 16th invocation
## MUST emit a `{.error.}` at compile time. The test harness in
## `tests/test_cap_counter.nim` runs `nim check` on this file and asserts
## the compiler exits non-zero with the cap-threshold message.
import nimfoot/cap_counter

nimfootCountRewrite()   # 1
nimfootCountRewrite()   # 2
nimfootCountRewrite()   # 3
nimfootCountRewrite()   # 4
nimfootCountRewrite()   # 5
nimfootCountRewrite()   # 6
nimfootCountRewrite()   # 7
nimfootCountRewrite()   # 8
nimfootCountRewrite()   # 9
nimfootCountRewrite()   # 10
nimfootCountRewrite()   # 11
nimfootCountRewrite()   # 12
nimfootCountRewrite()   # 13
nimfootCountRewrite()   # 14
nimfootCountRewrite()   # 15 — last one allowed
nimfootCountRewrite()   # 16 — must error
