## Module A: triggers the recursive TRM. Sits in its own module-body statement
## list. `hloBody` is invoked separately for A's top-level and B's top-level.
import nimfoot_q2

proc triggerRecursiveA*(): int =
  var x = 2
  var y = 3
  result = x * y  # recursive TRM trips here — inside A's proc
