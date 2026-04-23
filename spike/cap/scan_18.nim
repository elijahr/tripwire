## Generated test with 18 call sites.
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
sink = sink + target(10, 11)
sink = sink + target(11, 12)
sink = sink + target(12, 13)
sink = sink + target(13, 14)
sink = sink + target(14, 15)
sink = sink + target(15, 16)
sink = sink + target(16, 17)
sink = sink + target(17, 18)

echo "sink=", sink
echo "rewriteCount=", rewriteCount
echo "expected=18"
