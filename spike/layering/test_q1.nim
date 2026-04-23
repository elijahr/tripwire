## Q1: with both TRMs in scope via --import:q1_both_trms, call httpGet and
## observe both counters. Critical question: when the high-layer rewrite body
## calls socketSend internally, does the socket TRM also fire?
import targets

let r = httpGet("http://x")

echo "result: ", r
echo "httpRewrites: ", httpRewrites
echo "socketRewrites: ", socketRewrites
