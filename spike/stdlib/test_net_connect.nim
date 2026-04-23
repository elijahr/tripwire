## Target 5a: std/net.connect with distinct Port type.
## TRM declares port as Port (the declared type). Call site uses Port(80).
## `connect` is a void proc.
import std/net

var rewriteCount {.global.} = 0

template rewriteConnect{connect(socket, address, port)}(
    socket: Socket, address: string, port: Port) =
  inc(rewriteCount)
  discard

## Avoid opening a real socket: use a nil-ish socket? newSocket is safe
## (it just creates a handle). Don't actually call the underlying.
let s = newSocket()
s.connect("127.0.0.1", Port(80))
echo "rewriteCount=", rewriteCount
