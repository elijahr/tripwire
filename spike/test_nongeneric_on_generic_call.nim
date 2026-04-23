## Case 4a: can a NON-generic TRM `{target(a,b)}(a,b: int)` match
## a call to `targetGeneric[int](...)`? (Different name — should not.)
## Also tests whether a non-generic TRM on `target` fires when
## `target` is called via a generic wrapper (see case 5).
import nimfoot_auto_nogeneric, common

let r1 = target(2, 3)
let r2 = targetGeneric(2, 3)

echo "target(2,3)=", r1, " targetGeneric(2,3)=", r2
echo "rewriteCount: ", rewriteCount
