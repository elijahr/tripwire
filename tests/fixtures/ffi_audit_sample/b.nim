## Fixture for FFI audit scanner — module B.
##
## Contains exactly 1 importobjc pragma and 1 importjs pragma. Exercises
## the remaining two FFI pragma kinds the scanner claims to recognize.

proc objcHello() {.importobjc: "NSLog", nodecl.}

proc jsAlert(msg: cstring) {.importjs: "alert(@)".}
