## Q1 variant B observable. 2+3=5; expected result = 1005, count=1.
## If recursion happened we'd see count>1 or runaway.
import nimfoot_spy_q1b_obs, common_spy

let r1 = target(2, 3)
echo "r1=", r1, " count=", rewriteCount
