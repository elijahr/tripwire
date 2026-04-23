## High-layer TRM plugin: only intercepts httpGet. Its rewrite body calls
## socketSend internally — which, when the socket plugin is ALSO injected,
## will itself be intercepted (Q1 behavior).
import targets

var httpRewrites* {.global.} = 0

template rewriteHttpGet*{httpGet(url)}(url: string): string =
  inc(httpRewrites)
  socketSend(url, "GET intercepted\r\n")
  "fake-response"
