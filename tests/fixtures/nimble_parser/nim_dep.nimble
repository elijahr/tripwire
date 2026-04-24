# nim_dep.nimble — `requires "nim"` must be skipped. Nim itself is not
# a scannable dep; every Nim package declares a `nim` requirement and
# including it would scan the compiler's own stdlib which §5.5 forbids.
version = "0.1.0"
author = "tripwire-test"
description = "nim-dep fixture"
license = "MIT"

requires "nim >= 2.0"
requires "other"
