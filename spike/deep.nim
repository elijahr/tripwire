## Third layer — unaware of nimfoot_auto, called via `thirdparty_deep`.
import common
proc deepTarget*(x: int): int = target(x, 7)
