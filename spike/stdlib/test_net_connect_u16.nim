## Target 5b: same as 5a, but TRM declares port: uint16 (underlying base type).
## Tests whether distinct-type strictness blocks matching.
import std/net

var rewriteCount {.global.} = 0

template rewriteConnect{connect(socket, address, port)}(
    socket: Socket, address: string, port: uint16) =
  inc(rewriteCount)
  discard

let s = newSocket()
s.connect("127.0.0.1", Port(80))
echo "rewriteCount=", rewriteCount
