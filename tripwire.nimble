# Package

# `std/strutils` is needed for the string `in` operator used by the
# negative refc+threads build subtask in `task test` (design §8.1 F2,
# Task 3.9). NimScript's default `in` only handles set/openArray
# membership; string substring matching needs strutils.contains.
import std/strutils

version       = "0.0.1"
author        = "elijahr <elijahr+tripwire@gmail.com>"
description   = "Test mocking framework with three-guarantee enforcement"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0"
requires "parsetoml >= 0.7.0"

# Tasks

task test, "Run the full test matrix":
  # Cell 1: refc + sync
  exec "nim c --gc:refc --define:tripwireActive --import:tripwire/auto -r tests/all_tests.nim"
  # Cell 2: orc + sync
  exec "nim c --gc:orc --define:tripwireActive --import:tripwire/auto -r tests/all_tests.nim"
  # Cell 3: refc + unittest2
  exec "nim c --gc:refc --define:tripwireActive --define:tripwireUnittest2 --import:tripwire/auto -r tests/all_tests.nim"
  # Cell 4: orc + unittest2
  exec "nim c --gc:orc --define:tripwireActive --define:tripwireUnittest2 --import:tripwire/auto -r tests/all_tests.nim"
  # Cell 5: test_osproc_arrays.nim runs standalone — aggregating its
  # wrappers into all_tests.nim pushes cap_counter's 15-rewrite cap
  # (Defense 3).
  exec "nim c --gc:orc --define:tripwireActive -r tests/test_osproc_arrays.nim"
  # Cell 5b: test_firewall.nim runs standalone for the same reason as
  # cell 5 — its `tripwirePluginIntercept`-backed wrapper proc pushes
  # the aggregate one rewrite past the 15-cap.
  exec "nim c --gc:orc --define:tripwireActive --import:tripwire/auto -r tests/test_firewall.nim"
  # Cell 5c: test_auto_umbrella.nim runs standalone for the same
  # reason as cells 5 and 5b. Its “auto-only consumer” regression-guard
  # tests each emit a fresh TRM rewrite (one for the wrapper proc, one
  # for the firewall behavioral check), pushing the aggregate over the
  # 15-cap. Standalone, the cap is never approached.
  exec "nim c --gc:orc --define:tripwireActive --import:tripwire/auto -r tests/test_auto_umbrella.nim"
  # Cell 6: orc + chronos — opt-in via env var because chronos isn't in
  # `requires`. Set TRIPWIRE_TEST_CHRONOS=1 to enable; otherwise skip
  # the chronos cell.
  if existsEnv("TRIPWIRE_TEST_CHRONOS"):
    exec "nim c --gc:orc --define:tripwireActive --define:chronos --import:tripwire/auto -r tests/all_tests.nim"
  # Cell 6b: orc + chronos httpclient firewall plugin (standalone).
  # The chronos httpclient plugin's two firewall TRMs (`send`,
  # `fetch(uri)`) plus this test file's wrapper helpers push the
  # all_tests aggregate over Defense 3's 15-rewrites-per-compilation
  # -unit cap, so the file lives in its own cell. Same env-var gate as
  # cell 6 (chronos isn't in `requires`). Standalone-cell precedent:
  # test_osproc_arrays.nim / test_firewall.nim / test_auto_umbrella.nim.
  if existsEnv("TRIPWIRE_TEST_CHRONOS"):
    exec "nim c --gc:orc --define:tripwireActive --define:chronos --import:tripwire/auto -r tests/test_chronos_httpclient_firewall.nim"
  # Cell 7: arc + threads (v0.2 WI3, design §8.1, M-matrix). Runs the
  # main all_tests.nim aggregate under --mm:arc --threads:on to exercise
  # the v0.2 thread-safety amendment at the aggregate level, then runs
  # each tests/threads/*.nim file directly to cover the thread primitive
  # surface TODAY. The per-file invocations are redundant once Task 5.0.5
  # (WI5) aggregates tests/threads/*.nim imports into tests/all_tests.nim;
  # keep them here until that lands so cell #7 has meaningful thread
  # coverage today.
  #
  # --mm:arc (NOT --gc:orc) because Nim 2.2.6's orc cycle collector
  # SIGSEGVs during ref-Verifier teardown after a child thread has
  # pushed/popped the shared verifier (see spike/threads/
  # v02_gc_safety_REPORT.md Addendum). Design §8.1 lists arc and orc as
  # co-equal supported memory managers; arc is selected here to unblock
  # the matrix cell given 2.2.6's orc issue. The impl plan's literal
  # spec cited orc; this nimble task reflects the pragmatic choice made
  # in the spike report addendum.
  exec "nim c --mm:arc --threads:on --define:tripwireActive --define:tripwireUnittest2 --import:tripwire/auto -r tests/all_tests.nim"
  # Per-file thread tests — pending Task 5.0.5 aggregation. Each runs
  # under --mm:arc --threads:on for the same reason as the aggregate
  # invocation above.
  for threadTest in [
    "tests/threads/test_tripwire_thread_primitives_compile.nim",
    "tests/threads/test_tripwire_thread_basic.nim",
    "tests/threads/test_tripwire_thread_multi.nim",
    "tests/threads/test_tripwire_thread_exception.nim",
    "tests/threads/test_tripwire_thread_nested_sandbox.nim",
    "tests/threads/test_tripwire_thread_nested_sandbox_spawn.nim",
    "tests/threads/test_tripwire_thread_reject_chronos.nim",
    "tests/threads/test_tripwire_thread_reject_nested.nim",
  ]:
    exec "nim c --mm:arc --threads:on --define:tripwireActive --import:tripwire/auto -r " & threadTest
  # Negative refc+threads build subtask (design §8.1 F2, M-matrix). Uses
  # `nim check` (front-end type-check only) via gorgeEx so the
  # {.error.} at src/tripwire/threads.nim lines 23-26 fires without
  # triggering C codegen. Asserts exit code != 0 AND the expected error
  # text appears in stderr/output.
  let negBuild = gorgeEx(
    "nim check --gc:refc --threads:on --define:tripwireActive " &
    "tests/threads/test_refc_threads_rejected.nim")
  doAssert negBuild.exitCode != 0,
    "refc+threads negative build unexpectedly succeeded; F2 guard in " &
    "src/tripwire/threads.nim (lines 23-26) did not fire"
  # Match the full leading phrase so a future reorder (e.g.,
  # "--gc:arc or --gc:orc") still satisfies the assertion. The stable
  # semantic is "tripwireThread requires" + some GC list; both the
  # current and the reordered forms include that phrase.
  doAssert "tripwireThread requires --gc:orc or --gc:arc" in negBuild.output,
    "refc+threads negative build failed as expected, but the error " &
    "output did not contain the expected F2 message " &
    "(\"tripwireThread requires --gc:orc or --gc:arc\"). Output was:\n" &
    negBuild.output

task test_fast, "Run one config for quick iteration":
  exec "nim c --gc:orc --define:tripwireActive --import:tripwire/auto -r tests/all_tests.nim"

task test_defenses, "Run the Defense-1 compile-fail check":
  # NimScript has no execShellCmd; gorgeEx returns (output, exitCode).
  let r = gorgeEx("nim c --dry-run tests/fixtures/defense1_probe.nim")
  doAssert r.exitCode != 0, "Defense 1 did not fire as expected"
