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
import ./test_sandbox_named
# test_sandbox_passthrough.nim deliberately excluded from the aggregate —
# its single `tripwirePluginIntercept`-backed wrapper proc adds 1 TRM
# rewrite which pushes the aggregate over Defense 3's 15-rewrites-per-
# compilation-unit cap (cap_counter.nim). Mirrors the
# `test_osproc_arrays.nim` exclusion above. Run it directly:
#   nim c -r tests/test_sandbox_passthrough.nim
# It is also wired as a dedicated cell in `tripwire.nimble` so
# `nimble test` exercises it.
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

# WI3 v0.2 verifier-inheriting thread primitives (design §3).
# DEVIATION FROM IMPL PLAN TASK 5.0.5 (impl plan line 908 originally asked
# to aggregate `tests/threads/*.nim` here). Aggregation is infeasible:
# the 8 WI3 thread tests collectively register multiple TRMs via
# `mockable(...)` / `mock.expect`, and together with the existing
# aggregate usage they push the compilation-unit rewrite count past
# Defense 3's 15-cap (`src/tripwire/cap_counter.nim`). Bumping the cap
# past Nim's ~19 silent-drop threshold is unsafe and degrades Defense 3.
#
# Resolution: thread tests stay in `tripwire.nimble` cell #7's per-file
# loop (lines 61-71) as their permanent home. That loop runs each
# `tests/threads/*.nim` standalone under `--mm:arc --threads:on` and
# exercises the full thread-primitive surface. The aggregate here
# focuses on the cap-safe tests. `test_refc_threads_rejected.nim` is
# handled by the nimble `gorgeEx` negative-build probe (lines 77-91).
#
# A Nim 2.0+ `--threads:on` default is orthogonal: every cell already
# builds with threads:on, but the aggregate does not transitively import
# `tripwire/threads`, so the F2 guard at `threads.nim:23-26` never fires.

# WI4 v0.2 async registry + drain (design §4).
# These tests exercise asyncdispatch only (no tripwire/threads transitively),
# so they import cleanly in refc/orc/arc cells without unittest2.
#
# Gated on `not defined(tripwireUnittest2) and not defined(chronos)`
# because of two name-clash issues once these tests join the aggregate:
#
# (1) `-d:tripwireUnittest2`: `tripwire/integration_unittest` imports
#     `unittest2`, and each WI4 test imports `std/unittest` directly; the
#     two `Status` enums both export `OK`, making it ambiguous. Cells 3
#     and 4 skip.
# (2) `-d:chronos`: `tests/test_async_chronos.nim` (already aggregated)
#     imports chronos, and chronos exports a `Future` type that collides
#     with `asyncdispatch.Future` used in the WI4 tests' bare `Future[T]`
#     occurrences. Cell 6 skips.
#
# Resolution for both: aggregate the WI4 async tests only in cells where
# neither define is set. That covers cells 1 (refc sync), 2 (orc sync),
# and 7 (arc threads) — three distinct memory-manager configurations.
# Standalone runs in any cell remain green (the name-clashes are
# aggregate-only phenomena). Full-fidelity coverage on all 7 cells is
# v0.3 work (port to unittest2; qualify `Future` as `asyncdispatch.Future`).
#
# Two WI4 tests are deliberately excluded from the aggregate because their
# TRM rewrites push it past Defense 3's 15-rewrites-per-compilation-unit
# cap (cap_counter.nim), mirroring the `test_osproc_arrays.nim` pattern
# above:
#
#   - `test_async_check_basic.nim` — `mockable(computeThing(0))` adds 1
#     rewrite (the async happy path's mocked proc).
#   - `test_chronos_future_rejected.nim` — `osproc.execCmdEx` TRM adds
#     1 rewrite (the hermetic compile-probe shell-out).
#
# Both run cleanly standalone: `nim c -r tests/async_registry/<file>`
# (chronos probe additionally requires `-d:chronos` at compile time so
# `import chronos` resolves in the subprocess probe; see cell #6's env
# var gate). Each ran GREEN standalone in the chunk-4 Gate 2 matrix
# sweep. Not aggregating them here keeps the refc / orc / arc aggregate
# compiling; they are exercised via per-task gates today, and a
# dedicated per-file loop in `tripwire.nimble` is a candidate for
# Task 5.7's matrix-report follow-up.
when not defined(tripwireUnittest2) and not defined(chronos):
  import ./async_registry/test_async_check_leak_repro
  import ./async_registry/test_async_check_generation_repro
  import ./async_registry/test_async_check_drain_timeout
  import ./async_registry/test_plain_async_check_still_raises
