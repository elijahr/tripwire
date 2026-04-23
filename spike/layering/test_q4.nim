## Q4: confirm cross-module layering — two separate TRM plugin modules, each
## injected via --import:, target procs in targets.nim. Both should fire.
import targets

let r = httpGet("http://x")

echo "result: ", r
echo "httpRewrites: ", httpRewrites
echo "socketRewrites: ", socketRewrites
