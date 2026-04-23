## Q3: module A trips the recursive cap. Module B defines a non-recursive call
## site and is compiled in the same `nim c` invocation.
## Does B still get rewrites after A's sem work contaminated counter state?
import q3_modA, q3_modB, nimfoot_q2

let a = triggerRecursiveA()
let b = triggerNonRecursiveB()
echo "a=", a, " b=", b
echo "recursiveFireCount=", recursiveFireCount
echo "nimfootFireCount=", nimfootFireCount, " (expected 1)"
