## tests/async_registry/test_chronos_future_rejected.nim — Task 4.7.
##
## Pins the Chronos-Future compile-time rejection contract from design
## §4.1 (async_registry.nim lines 82-87): when a chronos ``Future[T]`` is
## passed to ``asyncCheckInSandbox`` under ``-d:chronos``, the template
## emits a ``{.warning.}`` with the canonical message AND does NOT
## register the Future against the current verifier's ``futureRegistry``.
##
## Mechanism: this test compiles (not runs) a tiny hermetic probe file
## via ``execCmdEx`` with ``-d:chronos`` and inspects the compiler
## output. The probe calls ``asyncCheckInSandbox`` on a ``chronos.Future``
## inside a ``sandbox:`` block. The warning is a compile-time
## diagnostic, so the test asserts on compiler stdout/stderr rather than
## on runtime behavior of the probe. ``nim check`` (front-end only) is
## used so chronos's large C backend never runs — fast and avoids
## linker-level variability between environments.
##
## Why NOT ``staticExec``: ``staticExec`` returns stdout only and does
## not surface the exit code in a single call on Nim 2.2.6. ``execCmdEx``
## at runtime returns (output, exitCode) together and is cleaner for the
## warning-AND-no-error assertion pair. The test file itself compiles
## WITHOUT ``-d:chronos``; it only shells out for the probe.
##
## Chronos availability: the test queries ``nimble path chronos`` at
## runtime and skips cleanly when chronos is not installed. Cell #6
## (orc+chronos; ``TRIPWIRE_TEST_CHRONOS=1`` in ``tripwire.nimble``)
## runs it with chronos installed and the substantive assertion path
## executes once ``tests/all_tests.nim`` aggregates this file (deferred
## to WI5 Task 5.0.5 per impl plan line 92 — aggregation owned by a
## single file owner to avoid parallel-work merge conflicts).
##
## Design citations: §4.1 (async registry surface), §11 (chronos non-
## goal), §9 (cell #6 chronos-rejected anchor).

import std/[unittest, strutils, osproc, os]

const
  # Verbatim from src/tripwire/async_registry.nim lines 84-86. A single-
  # line substring that is specific enough to distinguish the intended
  # warning from unrelated compiler chatter.
  ExpectedWarningText =
    "asyncCheckInSandbox does not support chronos Futures in v0.2"

  # Hermetic probe source. Imports chronos and calls
  # ``asyncCheckInSandbox`` on a ``chronos.Future``. If the template's
  # compile-time gate fires correctly, this compiles with a {.warning.}
  # but NO type-mismatch error.
  #
  # ``verify`` is imported so the ``sandbox:`` template's ``verifyAll``
  # call at sandbox exit resolves — matching the same discipline every
  # test in this suite follows (see test_async_check_basic.nim line 37).
  ProbeSource = """
import chronos
import tripwire/[sandbox, verify, async_registry]

proc probeMain() =
  sandbox:
    let fut = chronos.newFuture[int]("tripwire-test-chronos-probe")
    fut.complete(0)
    asyncCheckInSandbox(fut)

probeMain()
"""

proc chronosInstalled(): bool =
  ## True when ``nimble path chronos`` resolves. Cheap fork; runs once
  ## per test invocation.
  let (_, exitCode) = execCmdEx("nimble path chronos")
  exitCode == 0

proc repoSrcDir(): string =
  ## Locate the tripwire source directory by walking upward from this
  ## test file. Works under any nimble invocation that compiles from
  ## the repo root or a subdir.
  ##
  ## ``currentSourcePath`` is a compile-time macro; used here inside a
  ## runtime proc to pin the location relative to the test file rather
  ## than CWD (which varies between invocations).
  let testDir = currentSourcePath().parentDir()
  # tests/async_registry/test_chronos_future_rejected.nim -> repo root
  testDir.parentDir().parentDir() / "src"

suite "asyncCheckInSandbox: chronos Future compile-time rejection":
  test "warning fires AND no type-mismatch when chronos Future is passed under -d:chronos":
    if not chronosInstalled():
      # Chronos isn't in the declared deps (opt-in via
      # TRIPWIRE_TEST_CHRONOS=1 per tripwire.nimble lines 38-39). When
      # unavailable, the compile-time warning can't be observed from
      # this environment; skip cleanly rather than fake a pass.
      skip()
    else:
      # Write probe to a dedicated temp dir to isolate the nimcache.
      let probeDir = getTempDir() / "tripwire_chronos_reject_probe"
      createDir(probeDir)
      let probePath = probeDir / "probe.nim"
      writeFile(probePath, ProbeSource)

      # ``nim check`` runs the front-end only (no C codegen / linking),
      # which is fast and sufficient to surface a compile-time warning.
      # --path: points the front-end at tripwire's src/ so imports of
      # ``tripwire/...`` resolve without requiring a nimble install.
      # --hints:off suppresses routine info lines; warnings still surface.
      let cmd =
        "nim check --hints:off -d:chronos -d:tripwireActive --path:" &
        repoSrcDir().quoteShell() & " " & probePath.quoteShell()
      let (output, exitCode) = execCmdEx(cmd)

      # Assertion 1: the canonical warning text MUST appear. This is
      # the primary contract from design §4.1.
      check ExpectedWarningText in output

      # Assertion 2: NO type-mismatch error. The RED signal for the
      # template gate being broken is a "type mismatch" from the
      # compiler refusing to bind ``chronos.Future[T]`` to
      # ``asyncdispatch.Future[T]``. If this substring appears, the
      # template signature is filtering chronos out BEFORE the ``when``
      # branch can emit the warning.
      check "type mismatch" notin output

      # Assertion 3: ``nim check`` exits 0. A {.warning.} does NOT fail
      # compilation by default; if the exit code is non-zero, the probe
      # hit an actual error (not a warning) and the rejection path is
      # broken.
      check exitCode == 0

      # Cleanup.
      removeDir(probeDir)
