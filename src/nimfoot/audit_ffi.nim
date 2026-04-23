## nimfoot/audit_ffi.nim — Defense 2 Part 3 FFI audit stub.
##
## Full implementation — a transitive scan for `{.importc.}`,
## `{.dynlib.}`, and `{.header.}` pragmas across the consumer's
## dependency tree — is deferred to v0.1 per the v0 scope cuts. This
## stub exists so that:
##
##   1. `-d:nimfootAuditFFI` is a valid, documented define for the v0
##      release.
##   2. The facade (`src/nimfoot.nim`) can wire the import
##      unconditionally behind a `when defined(...)` today, then swap
##      in the real implementation in v0.1 without a facade change.
##   3. Users who opt in get a visible `{.hint.}` telling them the
##      feature is stubbed, so they don't silently assume FFI is
##      being audited.
##
## Defense 2 has three parts in the design:
##   Part 1: FFI-scope footer on every defect message (shipped in A3).
##   Part 2: opt-in activation gate for `import nimfoot` (shipped in G2).
##   Part 3: audit hook for FFI pragma scanning (this stub; real work
##           lands in v0.1).
##
## See `docs/design/v0.md` Appendix B for the deferred implementation
## sketch.
when defined(nimfootAuditFFI):
  {.hint: "FFI audit not implemented in v0; see Appendix B of the " &
    "design doc. Stub compiled under -d:nimfootAuditFFI; no pragma " &
    "scanning performed.".}
