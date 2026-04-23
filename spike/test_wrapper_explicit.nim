## Case 2: TRM fires in a wrapper that explicitly imports nimfoot_auto.
import nimfoot_auto
import thirdparty_explicit

let r1 = useTargetExplicit(5)
let r2 = useTargetExplicit(100)

echo "result: ", r1, " ", r2
echo "wrapper(explicit) rewriteCount: ", rewriteCount
