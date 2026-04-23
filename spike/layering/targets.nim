## Layered target procs. Low-layer `socketSend` is called internally by
## high-layer `httpGet`. Trivial implementations — the point is observability
## under TRM rewriting.

proc socketSend*(address: string, data: string) =
  # pretend this is a real send
  discard

proc httpGet*(url: string): string =
  socketSend(url, "GET / HTTP/1.1\r\n")
  return "real-response"
