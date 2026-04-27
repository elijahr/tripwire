## tripwire/errors.nim — full Defect hierarchy + constructors.
##
## Two roots descending from system:
##   TripwireDefect -> Defect       (verification failures; unswallowable)
##   TripwireError  -> CatchableError (API misuse; recoverable)

import std/[tables, editdistance]
import ./types
import ./plugin_base

type
  TripwireDefect* = object of Defect

  UnmockedInteractionDefect* = object of TripwireDefect
    pluginName*: string
    procName*: string
    fingerprint*: string
    args*: OrderedTable[string, string]
    site*: tuple[file: string, line, column: int]
    nearestMockHints*: seq[string]

  UnassertedInteractionsDefect* = object of TripwireDefect
    interactions*: seq[Interaction]
    verifierName*: string

  UnusedMocksDefect* = object of TripwireDefect
    mocks*: seq[Mock]
    verifierName*: string

  LeakedInteractionDefect* = object of TripwireDefect
    threadId*: int
    procName*: string

  OutsideSandboxNoPassthroughDefect* = object of TripwireDefect
    ## Raised when a TRM fires outside any sandbox under
    ## `[tripwire.firewall].guard = "warn"` for a plugin that does not
    ## support passthrough. The remediation is in the message: install
    ## a sandbox, or flip back to `guard = "error"` to make the missing
    ## sandbox loud at the standard `LeakedInteractionDefect` site.
    pluginName*: string
    procName*: string
    callsite*: tuple[filename: string, line: int]
    threadId*: int

  PostTestInteractionDefect* = object of TripwireDefect
    verifierName*: string
    generation*: int
    pluginName*: string
    procName*: string

  PendingAsyncDefect* = object of TripwireDefect
    testName*: string

  UnmockableContainerDefect* = object of TripwireDefect
    procName*: string
    containerType*: string
    site*: tuple[file: string, line, column: int]

  ChronosOnWorkerThreadDefect* = object of TripwireDefect
    ## Raised when a chronos import lands on a tripwireThread-wrapped
    ## worker. WI3 (threads) gate; see design chunk-2 brief, §2.3.
  NestedTripwireThreadDefect* = object of TripwireDefect
    ## Raised when a tripwireThread block fires from within another
    ## tripwireThread. WI3 (threads) gate; see design chunk-2 brief, §2.3.

  TripwireError* = object of CatchableError

  AssertionInsideSandboxError* = object of TripwireError
    site*: tuple[file: string, line, column: int]

const FFIScopeFooter* = "\n(tripwire intercepts Nim source calls only. " &
  "FFI ({.importc.}, {.dynlib.}, {.header.}) is not intercepted in v0. " &
  "See docs/concepts.md#scope.)"

# ---- Nearest-mock hints --------------------------------------------------

proc nearestMockHints*(actual: string, candidates: openArray[string],
                       maxDistance: int = 1): seq[string] {.raises: [].} =
  ## Returns candidates whose Levenshtein distance from `actual` is within
  ## (0, maxDistance]. Exact matches (distance 0) are suppressed because
  ## they would have matched upstream in `popMatchingMock` and never
  ## reached the unmocked-interaction path. Order is input (insertion)
  ## order — matches the registration order preserved by MockQueue.
  ## Uses `std/editdistance.editDistance` (Unicode-aware) so fingerprints
  ## containing URLs or non-ASCII identifiers compare correctly.
  result = @[]
  for c in candidates:
    let d = editDistance(actual, c)
    if d > 0 and d <= maxDistance:
      result.add(c)

# ---- Constructors --------------------------------------------------------

proc newUnmockedInteractionDefect*(pluginName, procName, fingerprint: string,
    site: tuple[file: string, line, column: int],
    plugin: Plugin = nil,
    candidates: openArray[string] = []):
      ref UnmockedInteractionDefect {.raises: [].} =
  ## If `plugin` is provided, the header uses `plugin.formatInteraction` for
  ## a verbose rendering; otherwise it falls back to `<plugin>.<proc>`.
  ##
  ## If `candidates` is non-empty, each fingerprint within edit distance 1
  ## of `fingerprint` is appended to the message as a "Did you mean:" hint
  ## block and stored on `nearestMockHints`. Additive — the field is
  ## always present and empty when no near-matches exist.
  let header =
    if plugin != nil:
      let synth = Interaction(plugin: plugin, procName: procName)
      "unmocked interaction: " & plugin.formatInteraction(synth)
    else:
      "unmocked interaction: " & pluginName & "." & procName
  let hints = nearestMockHints(fingerprint, candidates)
  var hintBlock = ""
  if hints.len > 0:
    hintBlock = "\n  Did you mean:"
    for h in hints:
      hintBlock.add("\n    - " & h)
  let msg = header &
    " at " & site.file & ":" & $site.line & ":" & $site.column &
    "\n  fingerprint: " & fingerprint & hintBlock & FFIScopeFooter
  result = (ref UnmockedInteractionDefect)(msg: msg,
    pluginName: pluginName, procName: procName, fingerprint: fingerprint,
    site: site, nearestMockHints: hints)

proc newUnassertedInteractionsDefect*(verifierName: string,
    interactions: seq[Interaction]):
      ref UnassertedInteractionsDefect {.raises: [].} =
  let msg = $interactions.len & " interactions recorded but not asserted " &
    "in verifier '" & verifierName & "'" & FFIScopeFooter
  result = (ref UnassertedInteractionsDefect)(msg: msg,
    verifierName: verifierName, interactions: interactions)

proc newUnusedMocksDefect*(verifierName: string,
    mocks: seq[Mock]): ref UnusedMocksDefect {.raises: [].} =
  let msg = $mocks.len & " mocks registered but never consumed in verifier '" &
    verifierName & "'" & FFIScopeFooter
  result = (ref UnusedMocksDefect)(msg: msg,
    verifierName: verifierName, mocks: mocks)

proc newLeakedInteractionDefect*(threadId: int,
    site: tuple[filename: string, line: int, column: int]):
      ref LeakedInteractionDefect {.raises: [].} =
  let msg = "TRM fired on thread " & $threadId & " with no active verifier " &
    "at " & site.filename & ":" & $site.line & FFIScopeFooter
  result = (ref LeakedInteractionDefect)(msg: msg, threadId: threadId)

proc newOutsideSandboxNoPassthroughDefect*(pluginName, procName: string,
    callsite: tuple[filename: string, line: int]):
      ref OutsideSandboxNoPassthroughDefect {.raises: [].} =
  ## `{.raises: [].}` is load-bearing: the constructor is called from
  ## inside TRM expansions that may sit inside chronos
  ## `async: (raises: [...])` procs. Matches `newLeakedInteractionDefect`'s
  ## annotation. Message format mirrors bigfoot's pedagogical guidance:
  ## point the operator at either installing a sandbox or flipping back
  ## to `guard = "error"` for the standard LeakedInteractionDefect.
  let msg = "plugin '" & pluginName &
    "' doesn't support outside-sandbox passthrough for '" & procName &
    "' at " & callsite.filename & ":" & $callsite.line &
    "; install a sandbox or set [tripwire.firewall].guard='error' to " &
    "make this fail loudly with the standard LeakedInteractionDefect" &
    FFIScopeFooter
  result = (ref OutsideSandboxNoPassthroughDefect)(msg: msg,
    pluginName: pluginName, procName: procName,
    callsite: (filename: callsite.filename, line: callsite.line),
    threadId: getThreadId())

proc newPostTestInteractionDefect*(verifierName: string, generation: int,
    pluginName, procName: string):
      ref PostTestInteractionDefect {.raises: [].} =
  let msg = "TRM fired against popped verifier '" & verifierName &
    "' (generation " & $generation & "): " & pluginName & "." & procName &
    FFIScopeFooter
  result = (ref PostTestInteractionDefect)(msg: msg,
    verifierName: verifierName, generation: generation,
    pluginName: pluginName, procName: procName)

proc newPendingAsyncDefect*(testName: string): ref PendingAsyncDefect =
  let msg = "test '" & testName & "' ended with pending async operations." &
    "\nUse `waitFor` to drain futures, or -d:tripwireAllowPendingAsync to" &
    " suppress." & FFIScopeFooter
  result = (ref PendingAsyncDefect)(msg: msg, testName: testName)

proc newPendingAsyncDefect*(msg: string,
    parent: ref Exception): ref PendingAsyncDefect =
  ## Drain-loop diagnostic overload (WI4). Stores `msg` verbatim (the
  ## caller composes it) and carries `parent` so rethrow chains compose
  ## correctly (design §4.4). `FFIScopeFooter` is appended, matching
  ## every other defect constructor in this file. `testName` is left
  ## empty — this overload is not a per-test wrap.
  ##
  ## NB: `parent` has no default. Callers wanting a detached defect must
  ## pass `nil` explicitly. This keeps the one-arg form
  ## `newPendingAsyncDefect(testName)` unambiguous; without the explicit
  ## second arg the compiler would not know which overload to pick.
  let fullMsg = msg & FFIScopeFooter
  result = (ref PendingAsyncDefect)(msg: fullMsg, parent: parent)

proc newChronosOnWorkerThreadDefect*(threadId: int,
    site: tuple[filename: string, line: int, column: int]): ref ChronosOnWorkerThreadDefect =
  let msg = "tripwireThread rejected: chronos on worker thread on thread " &
    $threadId & " at " & site.filename & ":" & $site.line & FFIScopeFooter
  result = (ref ChronosOnWorkerThreadDefect)(msg: msg)

proc newNestedTripwireThreadDefect*(threadId: int,
    site: tuple[filename: string, line: int, column: int]): ref NestedTripwireThreadDefect =
  let msg = "tripwireThread rejected: nested tripwire thread on thread " &
    $threadId & " at " & site.filename & ":" & $site.line & FFIScopeFooter
  result = (ref NestedTripwireThreadDefect)(msg: msg)

proc newUnmockableContainerDefect*(procName, containerType: string,
    site: tuple[filename: string, line: int, column: int]): ref UnmockableContainerDefect =
  let msg = "unmockable container type '" & containerType &
    "' passed to " & procName & " at " & site.filename & ":" &
    $site.line & FFIScopeFooter
  result = (ref UnmockableContainerDefect)(msg: msg,
    procName: procName, containerType: containerType,
    site: (file: site.filename, line: site.line, column: site.column))
