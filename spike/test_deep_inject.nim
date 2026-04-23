## Confirms --import:nimfoot_auto reaches N layers deep.
import thirdparty_deep

let r = chainCall(5)
echo "chainCall(5)=", r
echo "deep rewriteCount: ", rewriteCount
