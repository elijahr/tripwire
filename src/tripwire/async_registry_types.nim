## tripwire/async_registry_types.nim — shared type for async Future
## registry. Split from async_registry.nim to break the circular import
## between sandbox.nim (which carries a seq of these) and
## async_registry.nim (which mutates the seq).
import std/asyncfutures

type
  RegisteredFuture* = object
    fut*: FutureBase
    site*: tuple[filename: string, line, column: int]
