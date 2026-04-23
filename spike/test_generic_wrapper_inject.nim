## Case 5: generic wrapper via --import injection.
## thirdparty.useTargetGeneric[T] internally calls targetGeneric(x, T(1)).
## When instantiated with int, does the TRM fire on the inner call?
import thirdparty

let r1 = useTargetGeneric[int](5)
let r2 = useTargetGeneric(100)

echo "useTargetGeneric[int](5)=", r1, " useTargetGeneric(100)=", r2
echo "generic wrapper(inject) rewriteCountGeneric: ", rewriteCountGeneric
