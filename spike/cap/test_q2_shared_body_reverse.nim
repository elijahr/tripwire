## Q2 adversarial reverse: non-recursive first, then recursive — same proc body.
import nimfoot_q2, common_q2

proc mixed(): (int, int) =
  var x = 2
  var y = 3
  let addRes = addTarget(10, 20)   # non-recursive first
  let mulRes = x * y               # recursive trips after
  let addRes2 = addTarget(7, 8)    # non-recursive AFTER recursive cap
  result = (mulRes, addRes + addRes2)

let (a, b) = mixed()
echo "mulRes=", a, " addSum=", b
echo "recursiveFireCount=", recursiveFireCount
echo "nimfootFireCount=", nimfootFireCount, " (expected 2)"
