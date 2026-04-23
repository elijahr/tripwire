# Test build flags. `nimble test` passes these via the task command line,
# but direct `nim c -r tests/test_x.nim` also honors this file.
--path:"../src"
--warning:"UnusedImport:off"
--trmacros:on   # required — TRMs drive tripwire interception
