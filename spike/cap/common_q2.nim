## Q2 commons: two distinct targets. One is the multiplicative operand for the
## recursive commutativity TRM (diverges). The other is a plain add target with
## a `raw` twin for the nimfoot-style non-recursive TRM.
proc rawAddTarget*(x, y: int): int = x + y
proc addTarget*(x, y: int): int = rawAddTarget(x, y)
