# extra_hatch.nimble — minimal fixture for the mergeExtraRequires dedup
# helper. Auto-detected set includes `foo` and `qux`; the extras define
# supplies `foo,baz` — union must be `foo, qux, baz` (foo dedup'd).
version = "0.1.0"
author = "tripwire-test"
description = "extra-hatch fixture"
license = "MIT"

requires "foo"
requires "qux"
