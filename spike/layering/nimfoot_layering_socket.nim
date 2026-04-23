## Low-layer TRM plugin: only intercepts socketSend.
import targets

var socketRewrites* {.global.} = 0

template rewriteSocketSend*{socketSend(address, data)}(address, data: string) =
  inc(socketRewrites)
