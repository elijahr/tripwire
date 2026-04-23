## Module B: triggers the non-recursive TRM. Called from the main test after A.
import nimfoot_q2, common_q2

proc triggerNonRecursiveB*(): int =
  addTarget(10, 20)
