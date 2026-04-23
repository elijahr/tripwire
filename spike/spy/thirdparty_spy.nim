## Simulates an unmodified third-party library that calls target.
## Does NOT import the TRM module.
import common_spy

proc useTarget*(x: int): int = target(x, 1)
proc twoCalls*(x: int): int = target(x, 2) + target(x, 3)
