## Sanity check: bare chronos newFuture/complete/waitFor outside a TRM.
import chronos

let f = newFuture[string]("sanity")
complete(f, "hello")
echo "done: ", waitFor(f)
