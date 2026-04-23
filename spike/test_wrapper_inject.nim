## Case 3 (critical): entry point uses --import:nimfoot_auto; thirdparty.nim does NOT.
## If --import truly applies to every compilation unit, TRM fires inside useTarget.
import thirdparty

let r1 = useTarget(5)
let r2 = useTarget(100)

echo "result: ", r1, " ", r2
echo "wrapper(inject) rewriteCount: ", rewriteCount
## Sentinel visibility check: confirms --import:nimfoot_auto injected the module here.
echo "sentinel: ", nimfoot_auto_sentinel
