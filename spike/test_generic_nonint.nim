## Sanity: concrete-int TRM should NOT match float instantiations.
import nimfoot_auto, common

let r1 = targetGeneric(2.0, 3.0)
let r2 = targetGeneric[float](10.0, 20.0)

echo "targetGeneric(2.0,3.0)=", r1, " [float](10.0,20.0)=", r2
echo "rewriteCountGeneric (should be 0): ", rewriteCountGeneric
