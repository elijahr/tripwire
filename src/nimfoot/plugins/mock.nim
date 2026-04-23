## nimfoot/plugins/mock.nim — generic user-proc mocking.
##
## Design §5.1: MockPlugin is the passthrough-by-default plugin that
## intercepts arbitrary user procs via the `expect` DSL macro (F2).
## Each `expect fn(...)` invocation registers a mock keyed by procName
## + arg fingerprint; the matching TRM emitted at macro-expansion time
## routes calls to `fn` through `nimfootInterceptBody`.
import std/tables
import ../[types, registry, timeline, sandbox, verify, intercept, plugin_base]

type
  MockPlugin* = ref object of Plugin
  MockUserResponse*[T] = ref object of MockResponse
    returnValue*: T

proc realize*[T](r: MockUserResponse[T]): T = r.returnValue
  ## Not a method — Nim 2.2.6 multimethod dispatch doesn't support generic
  ## type parameters. Call sites use concrete T via the TRM body cast:
  ## `MockUserResponse[T](resp).realize()`.

method supportsPassthrough*(p: MockPlugin): bool = true
method passthroughFor*(p: MockPlugin, procName: string): bool = true

method assertableFields*(p: MockPlugin, i: Interaction): seq[string] =
  @["value"]

let mockPluginInstance* = MockPlugin(name: "mock", enabled: true)
registerPlugin(mockPluginInstance)
