## Q2a injected into unmodified third-party.
import thirdparty_spy
let a = useTarget(10)
let b = twoCalls(5)
echo "a=", a, " b=", b, " count=", rewriteCount
