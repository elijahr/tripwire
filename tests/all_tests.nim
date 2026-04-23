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
# test_nimble_manifest.nim deliberately excluded — it shells out to `nimble tasks`
# which, when invoked under `nimble test`, creates a recursive-invocation loop.
