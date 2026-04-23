## Variant: thirdparty with explicit import of nimfoot_auto (Case 2).
import common
import nimfoot_auto

proc useTargetExplicit*(x: int): int = target(x, 1)

proc useTargetGenericExplicit*[T](x: T): T = targetGeneric(x, T(1))
