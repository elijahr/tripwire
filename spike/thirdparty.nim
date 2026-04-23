## Simulates an unmodified third-party library that calls target/targetGeneric.
## Does NOT import nimfoot_auto.
import common

proc useTarget*(x: int): int = target(x, 1)

proc useTargetGeneric*[T](x: T): T = targetGeneric(x, T(1))

proc marker*(): string = "thirdparty reachable"
