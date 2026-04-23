import targets
httpInterceptEnabled = false
echo "calling with flag=false..."
let r = httpGet("http://x")
echo "result: ", r
echo "httpRewrites: ", httpRewrites
