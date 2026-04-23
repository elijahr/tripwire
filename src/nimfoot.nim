## nimfoot — test mocking with three-guarantee enforcement.
## Full facade emitted in Track G.
when not defined(nimfootActive) and not defined(nimfootAllowInactive):
  {.error: "nimfoot was imported but not activated. " &
    "Add `--import:\"nimfoot/auto\"` and `--define:\"nimfootActive\"` " &
    "to your test config.nims, or `--define:\"nimfootAllowInactive\"` " &
    "to suppress this error.".}
