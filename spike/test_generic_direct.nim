## Case 4 (generics, direct): does the generic TRM match a concrete int call site?
import nimfoot_auto, common

let r1 = targetGeneric(2, 3)
let r2 = targetGeneric[int](10, 20)

echo "result: ", r1, " ", r2
echo "generic direct rewriteCountGeneric: ", rewriteCountGeneric
