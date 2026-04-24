# conditional.nimble — documented limit: conditional `requires` inside
# `when` / `if` blocks are INCLUDED regardless of syntactic context.
# The parser scans line-by-line and does not evaluate control flow.
version = "0.1.0"
author = "tripwire-test"
description = "conditional fixture"
license = "MIT"

requires "alpha"

when defined(someFeature):
  requires "beta >= 2.0"

if (1 + 1 == 2):
  requires "gamma"
