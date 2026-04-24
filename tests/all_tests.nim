## tests/all_tests.nim — aggregate harness run by `nimble test`.
##
## Chunk 1 (Foundation) tests only. Later chunks add more imports here.

import ./test_types
import ./test_errors
import ./test_errors_facade  # Task 2.4: compile-time gate for facade re-exports
import ./test_hints
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
import ./test_integration_unittest2  # gated internally by `when defined(tripwireUnittest2)`
import ./test_auto_umbrella
import ./test_defenses
# H2: framework's existence proof (three guarantees).
import ./test_self_three_guarantees
# H4/H5/H6: documentation presence guardrails.
import ./test_docs_presence
# Defense 2 Part 3 FFI audit: real scoped scanner (replaces the v0 stub).
import ./test_audit_ffi
# WI1 v0.2 audit_ffi auto-discovery test pack (design §5.2, §5.3, §5.5).
import ./audit_ffi/test_auto_projectpath
import ./audit_ffi/test_auto_transitive_optin
import ./audit_ffi/test_nimble_parser_limits
import ./audit_ffi/test_stdlib_not_scanned
# test_nimble_manifest.nim deliberately excluded — it shells out to `nimble tasks`
# which, when invoked under `nimble test`, creates a recursive-invocation loop.
