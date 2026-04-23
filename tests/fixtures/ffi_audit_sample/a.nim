## Fixture for FFI audit scanner — module A.
##
## Contains exactly 2 real FFI pragmas (importc + importcpp). The
## docstring deliberately mentions the bare words importc and importjs
## WITHOUT the pragma-start delimiter so the scanner's pragma-syntax
## regex does not match them. Only the two real pragmas below are
## counted.
##
## Scanner truth check: this file must count as 2 FFI procs.

proc strlen_ffi(s: cstring): csize_t {.importc: "strlen", nodecl.}

proc sqrtCpp(x: cdouble): cdouble {.importcpp: "std::sqrt(@)".}
