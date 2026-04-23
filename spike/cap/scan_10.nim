## Generated test with 10 call sites.
import nimfoot_q1, common_q1

var sink = 0
sink = sink + target(0, 1)
sink = sink + target(1, 2)
sink = sink + target(2, 3)
sink = sink + target(3, 4)
sink = sink + target(4, 5)
sink = sink + target(5, 6)
sink = sink + target(6, 7)
sink = sink + target(7, 8)
sink = sink + target(8, 9)
sink = sink + target(9, 10)

echo "sink=", sink
echo "rewriteCount=", rewriteCount
echo "expected=10"
