## Q2 ordering B: non-recursive TRM fires FIRST, then recursive trips.
## Inverse of ordering A — checks if order of appearance matters for
## evalTemplateCounter state.
import nimfoot_q2, common_q2

proc triggerNonRecursive(): int =
  result = addTarget(10, 20)

proc triggerRecursive(): int =
  var x = 2
  var y = 3
  result = x * y

let b = triggerNonRecursive()
let c = triggerNonRecursive()
let d = triggerNonRecursive()
let a = triggerRecursive()
let e = triggerNonRecursive()  # post-recursive-trip call site

echo "recursive result=", a
echo "nimfoot results=", b, " ", c, " ", d, " ", e
echo "recursiveFireCount=", recursiveFireCount
echo "nimfootFireCount=", nimfootFireCount, " (expected 4)"
