## tests/test_outside_sandbox_guard.nim - A4'''.4 outside-sandbox guard mode.
##
## Wires `[tripwire.firewall].guard = "warn"` from tripwire.toml into the
## TRM-body chokepoints (intercept.nim, plugin_intercept.nim). Seven cases
## per design doc 2026-04-26-tripwire-guard-mode-design.md section 6:
##
##   1. Default config (guard unset): outside-sandbox call raises
##      LeakedInteractionDefect.
##   2. guard = "error" explicit: same as case 1.
##   3. guard = "warn" + passthrough-capable plugin: stderr warning emitted,
##      real impl runs, return value matches.
##   4. guard = "warn" + non-passthrough plugin: raises
##      OutsideSandboxNoPassthroughDefect.
##   5. guard = "warn" inside sandbox: inside-sandbox UnmockedInteractionDefect
##      semantics unchanged.
##   6. Multi-thread isolation: thread-A reload only updates thread-A's
##      config memo; thread-B keeps old behavior.
##   7. Legacy flat [firewall] block (not [tripwire.firewall]): same wiring.
##
## Stderr capture uses POSIX dup2 to a tempfile.

import std/[unittest, os, options, posix, locks, strutils, times]
import tripwire/[types, errors, timeline, sandbox, verify, intercept,
                 cap_counter, config, firewall_types, plugin_base]
import tripwire/plugins/plugin_intercept

# ---- Test plugins -------------------------------------------------------
# PassthroughPlugin: supportsPassthrough() = true. Mirrors MockPlugin's
# safety profile (no destructive side effects).
type
  PassthroughPlugin* = ref object of Plugin
  PassthroughResp* = ref object of MockResponse
    val*: int
  NoPassthroughPlugin* = ref object of Plugin
  NoPassthroughResp* = ref object of MockResponse
    val*: int

method realize*(r: PassthroughResp): int = r.val
method realize*(r: NoPassthroughResp): int = r.val

method supportsPassthrough*(p: PassthroughPlugin): bool {.raises: [].} = true
method passthroughFor*(p: PassthroughPlugin,
                       procName: string): bool {.raises: [].} = true
# NoPassthroughPlugin inherits the base default (supportsPassthrough=false).

let passthroughPlugin* = PassthroughPlugin(name: "passthroughPlug",
                                           enabled: true)
let noPassthroughPlugin* = NoPassthroughPlugin(name: "noPassthroughPlug",
                                               enabled: true)

# ---- Wrappers exercising the TRM combinators ----------------------------
# `outsideSandboxPassthroughCall` exercises the plugin_intercept.nim
# combinator (the typedesc-workaround path used by every real plugin).
proc outsideSandboxPassthroughCall(x: int): int =
  tripwirePluginIntercept(passthroughPlugin, "outsideSandboxPassthroughCall",
    fingerprintOf("outsideSandboxPassthroughCall", @[$x]),
    PassthroughResp):
    {.noRewrite.}:
      x * 7

# `outsideSandboxNoPassthroughCall` exercises the same combinator with a
# plugin whose supportsPassthrough()=false. Under guard="warn" this must
# raise OutsideSandboxNoPassthroughDefect.
proc outsideSandboxNoPassthroughCall(x: int): int =
  tripwirePluginIntercept(noPassthroughPlugin,
    "outsideSandboxNoPassthroughCall",
    fingerprintOf("outsideSandboxNoPassthroughCall", @[$x]),
    NoPassthroughResp):
    {.noRewrite.}:
      x * 11

# ---- Helpers ------------------------------------------------------------

proc clearVerifierStack() =
  while currentVerifier() != nil:
    discard popVerifier()

proc writeTempToml(content: string): string =
  ## Write `content` to a unique temp toml. Caller deletes when done.
  result = getTempDir() / ("tripwire_guard_" & $getCurrentProcessId() &
                            "_" & $epochTime() & ".toml")
  writeFile(result, content)

proc applyConfig(tomlContent: string): string =
  ## Write a temp toml, point TRIPWIRE_CONFIG at it, force a reload.
  ## Returns the path so the caller can delete it.
  result = writeTempToml(tomlContent)
  putEnv("TRIPWIRE_CONFIG", result)
  reloadConfig()

proc clearConfig(path: string) =
  ## Reverse of applyConfig: drop env var, drop memo, delete temp file.
  delEnv("TRIPWIRE_CONFIG")
  reloadConfig()
  if fileExists(path):
    removeFile(path)

proc captureStderr(action: proc() {.gcsafe.}): string =
  ## POSIX dup2-based stderr capture. Saves stderr's fd, redirects to a
  ## tempfile, runs `action`, restores stderr, reads the file.
  let tmpPath = getTempDir() / ("tripwire_stderr_" & $getCurrentProcessId() &
                                 "_" & $epochTime() & ".log")
  let savedFd = dup(2)
  doAssert savedFd != -1, "dup(2) failed"
  let tmpFd = open(tmpPath.cstring, O_RDWR or O_CREAT or O_TRUNC, 0o644)
  doAssert tmpFd != -1, "open tempfile for stderr failed"
  doAssert dup2(tmpFd, 2) != -1, "dup2 to stderr failed"
  discard close(tmpFd)
  try:
    action()
  finally:
    stderr.flushFile()
    doAssert dup2(savedFd, 2) != -1, "dup2 restore stderr failed"
    discard close(savedFd)
  result = readFile(tmpPath)
  removeFile(tmpPath)

# ---- Threadvar isolation case ------------------------------------------
# Thread B parks on a lock and reports its outcome on a shared channel
# without ever invalidating its own configMemo. Thread A is the orchestrator.

type
  ThreadBOutcome = object
    raisedLeaked: bool
    raisedNoPassthrough: bool
    raisedOther: bool
    threadStarted: bool

var threadBOutcomeLock: Lock
var threadBOutcomeReady: Cond
var threadBStartReady: Cond
var threadBOutcome: ThreadBOutcome
var threadBSignaled: bool

proc threadBProc() {.thread.} =
  # parsetoml's parseFile is not GC-safe by Nim's effect tracker, but
  # the threadvar memo guarantees B never re-parses A's TRIPWIRE_CONFIG
  # path - B's first getConfig() call captures the cwd-walk default
  # before A mutates the env. The cast asserts that contract.
  {.cast(gcsafe).}:
    # Memoize the default config on this thread's threadvar BEFORE
    # acquiring any lock. This is the load-bearing precondition for
    # the thread-isolation assertion.
    discard getConfig()
    acquire(threadBOutcomeLock)
    threadBOutcome.threadStarted = true
    signal(threadBStartReady)
    while not threadBSignaled:
      wait(threadBOutcomeReady, threadBOutcomeLock)
    release(threadBOutcomeLock)
    # Now perform an outside-sandbox call. With the threadvar memo
    # captured before A's TRIPWIRE_CONFIG mutation, B's getConfig()
    # returns the original (default) config -> guard=fmError ->
    # LeakedInteractionDefect.
    acquire(threadBOutcomeLock)
    try:
      discard outsideSandboxNoPassthroughCall(99)
      threadBOutcome.raisedOther = true
    except LeakedInteractionDefect:
      threadBOutcome.raisedLeaked = true
    except OutsideSandboxNoPassthroughDefect:
      threadBOutcome.raisedNoPassthrough = true
    except CatchableError, Defect:
      threadBOutcome.raisedOther = true
    signal(threadBOutcomeReady)
    release(threadBOutcomeLock)

# ---- Suite --------------------------------------------------------------

suite "outside-sandbox guard mode (A4'''.4)":
  setup:
    clearVerifierStack()
    delEnv("TRIPWIRE_CONFIG")
    reloadConfig()

  teardown:
    clearVerifierStack()
    delEnv("TRIPWIRE_CONFIG")
    reloadConfig()

  test "case 1: default config -> LeakedInteractionDefect":
    # No TRIPWIRE_CONFIG set; reloadConfig() leaves cwd-walk discovery; in
    # the test cwd there should be no tripwire.toml committed at the
    # package root (verified by `loadConfig(none)` returning defaults).
    check getConfig().firewall.guard == fmError
    expect LeakedInteractionDefect:
      discard outsideSandboxNoPassthroughCall(3)

  test "case 2: guard='error' -> LeakedInteractionDefect":
    let path = applyConfig("""
[tripwire.firewall]
guard = "error"
""")
    try:
      check getConfig().firewall.guard == fmError
      expect LeakedInteractionDefect:
        discard outsideSandboxNoPassthroughCall(4)
    finally:
      clearConfig(path)

  test "case 3: guard='warn' + passthrough plugin -> stderr+passthrough":
    let path = applyConfig("""
[tripwire.firewall]
guard = "warn"
""")
    try:
      check getConfig().firewall.guard == fmWarn
      var ret = 0
      let captured = captureStderr(proc() {.gcsafe.} =
        ret = outsideSandboxPassthroughCall(6))
      check ret == 42  # 6 * 7
      let expectedPrefix = "tripwire(guard=warn): unmocked " &
        passthroughPlugin.name & ".outsideSandboxPassthroughCall at "
      # Exact-equality slice: captured stderr begins with prefix, ends
      # with "\n", and middle is `<file>:<line>` from instantiationInfo()
      # at the tripwirePluginIntercept call site inside the wrapper proc.
      check captured[0 ..< expectedPrefix.len] == expectedPrefix
      check captured[captured.len - 1] == '\n'
      # Middle slice is "<file>:<line>".
      let middle = captured[expectedPrefix.len ..< captured.len - 1]
      let colonIdx = middle.rfind(':')
      check colonIdx > 0
      let filePart = middle[0 ..< colonIdx]
      let linePart = middle[colonIdx + 1 ..< middle.len]
      # `instantiationInfo()` returns the relative path captured at
      # compile time (the basename when the source path is itself
      # relative); compare on basename to be robust to compiler-relative
      # vs absolute path differences.
      check filePart.extractFilename == currentSourcePath().extractFilename
      # Line is the line of tripwirePluginIntercept(passthroughPlugin, ...)
      # inside outsideSandboxPassthroughCall. Parse-as-int sanity check
      # is sufficient; full-equality on the filename above is the
      # load-bearing check.
      check parseInt(linePart) > 0
    finally:
      clearConfig(path)

  test "case 4: guard='warn' + no-passthrough -> NoPassthroughDefect":
    let path = applyConfig("""
[tripwire.firewall]
guard = "warn"
""")
    try:
      check getConfig().firewall.guard == fmWarn
      var caught: ref OutsideSandboxNoPassthroughDefect = nil
      try:
        discard outsideSandboxNoPassthroughCall(5)
      except OutsideSandboxNoPassthroughDefect as e:
        caught = e
      check caught != nil
      check caught.pluginName == noPassthroughPlugin.name
      check caught.procName == "outsideSandboxNoPassthroughCall"
      check caught.callsite.filename.extractFilename ==
        currentSourcePath().extractFilename
      check caught.callsite.line > 0
      # Reconstruct the expected message using the stored callsite,
      # matching newOutsideSandboxNoPassthroughDefect's exact format.
      # FFIScopeFooter is appended by the constructor.
      let expectedMsg = "plugin '" & noPassthroughPlugin.name &
        "' doesn't support outside-sandbox passthrough for " &
        "'outsideSandboxNoPassthroughCall' at " &
        caught.callsite.filename & ":" & $caught.callsite.line &
        "; install a sandbox or set [tripwire.firewall].guard='error' " &
        "to make this fail loudly with the standard " &
        "LeakedInteractionDefect" & FFIScopeFooter
      check caught.msg == expectedMsg
    finally:
      clearConfig(path)

  test "case 5: guard='warn' inside sandbox -> UnmockedInteractionDefect":
    # Inside-sandbox firewall semantics are unchanged. Verifier defaults
    # firewallMode=fmError (per newVerifier) regardless of project config.
    let path = applyConfig("""
[tripwire.firewall]
guard = "warn"
""")
    try:
      check getConfig().firewall.guard == fmWarn
      expect UnmockedInteractionDefect:
        sandbox:
          discard outsideSandboxNoPassthroughCall(7)
    finally:
      clearConfig(path)

  test "case 6: thread B's threadvar memo isolated from thread A":
    # F2 from design: spawn thread B FIRST, have it memoize default
    # config and park. Then thread A: write toml with guard='warn',
    # set TRIPWIRE_CONFIG, call reloadConfig() on A's thread, do an
    # outside-sandbox passthrough call (must succeed). Signal B.
    # Thread B does its own outside-sandbox call WITHOUT calling
    # reloadConfig() and asserts the OLD (default) behavior, proving
    # threadvar isolation.
    initLock(threadBOutcomeLock)
    initCond(threadBOutcomeReady)
    initCond(threadBStartReady)
    threadBOutcome = ThreadBOutcome()
    threadBSignaled = false
    var b: Thread[void]
    createThread(b, threadBProc)
    # Wait for B to start.
    acquire(threadBOutcomeLock)
    while not threadBOutcome.threadStarted:
      wait(threadBStartReady, threadBOutcomeLock)
    release(threadBOutcomeLock)
    # Thread A: apply guard='warn'.
    let path = applyConfig("""
[tripwire.firewall]
guard = "warn"
""")
    try:
      check getConfig().firewall.guard == fmWarn
      # Thread A passthrough call succeeds.
      var ret = 0
      discard captureStderr(proc() {.gcsafe.} =
        ret = outsideSandboxPassthroughCall(2))
      check ret == 14  # 2 * 7
      # Signal thread B; do NOT call reloadConfig from A's perspective on B.
      acquire(threadBOutcomeLock)
      threadBSignaled = true
      signal(threadBOutcomeReady)
      # Wait for B to report.
      while not (threadBOutcome.raisedLeaked or
                 threadBOutcome.raisedNoPassthrough or
                 threadBOutcome.raisedOther):
        wait(threadBOutcomeReady, threadBOutcomeLock)
      release(threadBOutcomeLock)
      joinThread(b)
      # B memoized BEFORE A's TRIPWIRE_CONFIG was set, so B's getConfig
      # returns its own thread-local memo (default fmError) -> LeakedDefect.
      check threadBOutcome.raisedLeaked == true
      check threadBOutcome.raisedNoPassthrough == false
      check threadBOutcome.raisedOther == false
    finally:
      clearConfig(path)
      deinitCond(threadBOutcomeReady)
      deinitCond(threadBStartReady)
      deinitLock(threadBOutcomeLock)

  test "case 7: legacy flat [firewall] block also wires guard='warn'":
    # The legacy fall-through at config.nim's loadConfig consults
    # toml["firewall"] only if the [tripwire.firewall] block left
    # defaults intact, so the flat form must NOT also include a
    # [tripwire.firewall] block.
    let path = applyConfig("""
[firewall]
guard = "warn"
""")
    try:
      check getConfig().firewall.guard == fmWarn
      var ret = 0
      let captured = captureStderr(proc() {.gcsafe.} =
        ret = outsideSandboxPassthroughCall(3))
      check ret == 21  # 3 * 7
      let expectedPrefix = "tripwire(guard=warn): unmocked " &
        passthroughPlugin.name & ".outsideSandboxPassthroughCall at "
      check captured[0 ..< expectedPrefix.len] == expectedPrefix
      check captured[captured.len - 1] == '\n'
    finally:
      clearConfig(path)
