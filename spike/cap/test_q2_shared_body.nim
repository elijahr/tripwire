## Q2 adversarial: recursive and non-recursive call sites in the SAME proc body,
## sharing the same hloLoopDetector budget (300) and the same evalTemplateCounter
## flow. If contamination happens anywhere, it's here.
import nimfoot_q2, common_q2

proc mixed(): (int, int) =
  var x = 2
  var y = 3
  let mulRes = x * y          # recursive TRM trips here
  let addRes = addTarget(10, 20)  # non-recursive right after
  result = (mulRes, addRes)

let (a, b) = mixed()
echo "mulRes=", a, " addRes=", b
echo "recursiveFireCount=", recursiveFireCount
echo "nimfootFireCount=", nimfootFireCount, " (expected 1)"
