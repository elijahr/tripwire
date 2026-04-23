## Q1 variant B — TRM reaches into third-party via --import:
## Expected: each call fires exactly once, real sums preserved.
import thirdparty_spy

let a = useTarget(10)       ## target(10,1) = 11
let b = twoCalls(5)         ## target(5,2)+target(5,3) = 7+8 = 15
echo "a=", a, " b=", b, " count=", rewriteCount
## Expected: a=11 b=15 count=3
