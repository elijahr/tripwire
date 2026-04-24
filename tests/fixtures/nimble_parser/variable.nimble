# variable.nimble — documented miss: variable expansion in `requires`.
# Any `requires` line containing `&` or lacking a matched quote pair is
# skipped because the parser cannot resolve the value at scan time.
version = "0.1.0"
author = "tripwire-test"
description = "variable fixture"
license = "MIT"

const chronosVer = "4.0"
requires "chronos >= " & chronosVer
