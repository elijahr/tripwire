## Q1 variant B — multiple call sites in separate procs.
## Each call should fire exactly once.
import nimfoot_spy_q1b, common_spy

proc siteA(): int = target(2, 3)
proc siteB(): int = target(10, 20)
proc siteC(x: int): int = target(x, x)

let a = siteA()
let b = siteB()
let c = siteC(7)
echo "a=", a, " b=", b, " c=", c, " count=", rewriteCount
## Expected: a=5, b=30, c=14, count=3
