import nimfoot_spy_q2a, common_spy

proc siteA(): int = target(2, 3)
proc siteB(): int = target(10, 20)
proc siteC(x: int): int = target(x, x)

let a = siteA()
let b = siteB()
let c = siteC(7)
echo "a=", a, " b=", b, " c=", c, " count=", rewriteCount
