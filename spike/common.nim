## Target procs under test. Kept trivial to isolate TRM behavior.
proc target*(x, y: int): int = x + y
proc targetGeneric*[T](x, y: T): T = x + y
