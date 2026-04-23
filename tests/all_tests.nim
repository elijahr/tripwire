## tests/all_tests.nim — aggregate harness run by `nimble test`.
##
## Chunk 1 (Foundation) tests only. Later chunks add more imports here.

import ./test_types
import ./test_errors
import ./test_plugin_base
import ./test_registry
import ./test_timeline
import ./test_sandbox
import ./test_verifier
import ./test_context
import ./test_intercept
import ./test_config
import ./test_macros
import ./test_cap_counter
import ./test_async_asyncdispatch
import ./test_async_chronos  # gated internally by `when defined(chronos)`
import ./test_mock_plugin
import ./test_mock_expect
import ./test_mock_assert
import ./test_httpclient_plugin
import ./test_httpclient_async
import ./test_httpclient_wrappers
import ./test_osproc_plugin
# test_osproc_arrays.nim deliberately excluded from the aggregate harness —
# its 3 wrapper procs + the existing test_osproc_plugin wrappers + every
# other test file's wrappers push the aggregate over Defense 3's 15
# rewrites-per-compilation-unit cap (cap_counter.nim). Run it directly:
#   nim c -r tests/test_osproc_arrays.nim
import ./test_integration_unittest
import ./test_integration_unittest2  # gated internally by `when defined(nimfootUnittest2)`
import ./test_auto_umbrella
# test_nimble_manifest.nim deliberately excluded — it shells out to `nimble tasks`
# which, when invoked under `nimble test`, creates a recursive-invocation loop.
