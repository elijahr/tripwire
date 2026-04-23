## Target and its raw twin. `rawTarget` is intentionally a DIFFERENT name so the
## TRM output doesn't re-match the pattern — per-call-site depth stays at 1.
proc rawTarget*(x, y: int): int = x + y
proc target*(x, y: int): int = rawTarget(x, y)
