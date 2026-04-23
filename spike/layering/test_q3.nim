import targets

echo "--- flag enabled ---"
httpInterceptEnabled = true
let r1 = httpGet("http://x")
echo "result: ", r1
echo "httpRewrites: ", httpRewrites

echo "--- flag disabled ---"
httpInterceptEnabled = false
let r2 = httpGet("http://x")
echo "result: ", r2
echo "httpRewrites: ", httpRewrites
