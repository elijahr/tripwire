## Case 1 (baseline): TRM defined in A, called directly from B which imports A.
import nimfoot_auto, common

let r1 = target(2, 3)
let r2 = target(10, 20)

echo "result: ", r1, " ", r2
echo "direct rewriteCount: ", rewriteCount
