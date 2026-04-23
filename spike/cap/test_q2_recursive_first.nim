## Q2 ordering A: recursive TRM trips FIRST, then non-recursive TRM.
## Each fires inside its own proc (fresh hloLoopDetector per proc).
import nimfoot_q2, common_q2

proc triggerRecursive(): int =
  ## One `*` site — recursive TRM will recursively swap until depth cap fires.
  ## Uses `var` operands so the `*` is not const-folded at sem time.
  var x = 2
  var y = 3
  result = x * y

proc triggerNonRecursive(): int =
  ## Distinct call site for the nimfoot-style TRM.
  result = addTarget(10, 20)

let a = triggerRecursive()
let b = triggerNonRecursive()
let c = triggerNonRecursive()
let d = triggerNonRecursive()

echo "recursive result=", a
echo "nimfoot results=", b, " ", c, " ", d
echo "recursiveFireCount=", recursiveFireCount
echo "nimfootFireCount=", nimfootFireCount, " (expected 3)"
