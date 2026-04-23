## Fixture for FFI audit scanner — module C (clean).
##
## Contains ZERO FFI pragmas. Exists so the scanner's per-file output
## can be tested against a file that must contribute 0 matches. The
## word "importc" appearing in this docstring and in the following
## string literal must not be counted.

const s = "this string mentions importc but is not a pragma"

proc double(x: int): int = x * 2
