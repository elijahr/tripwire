# simple.nimble — happy path fixture for test_nimble_parser_limits.
# Two ordinary single-line `requires` entries. Version-bound stripping
# must apply to the second entry.
version = "0.1.0"
author = "tripwire-test"
description = "simple fixture"
license = "MIT"

requires "foo"
requires "bar >= 1.0"
