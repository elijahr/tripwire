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

  TripwireError* = object of CatchableError

  AssertionInsideSandboxError* = object of TripwireError
    site*: tuple[file: string, line, column: int]

const FFIScopeFooter* = "\n(tripwire intercepts Nim source calls only. " &
  "FFI ({.importc.}, {.dynlib.}, {.header.}) is not intercepted in v0. " &
  "See docs/concepts.md#scope.)"

# ---- Nearest-mock hints --------------------------------------------------

proc nearestMockHints*(actual: string, candidates: openArray[string],
                       maxDistance: int = 1): seq[string] =
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
    candidates: openArray[string] = []): ref UnmockedInteractionDefect =
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
    interactions: seq[Interaction]): ref UnassertedInteractionsDefect =
  let msg = $interactions.len & " interactions recorded but not asserted " &
    "in verifier '" & verifierName & "'" & FFIScopeFooter
  result = (ref UnassertedInteractionsDefect)(msg: msg,
    verifierName: verifierName, interactions: interactions)

proc newUnusedMocksDefect*(verifierName: string,
    mocks: seq[Mock]): ref UnusedMocksDefect =
  let msg = $mocks.len & " mocks registered but never consumed in verifier '" &
    verifierName & "'" & FFIScopeFooter
  result = (ref UnusedMocksDefect)(msg: msg,
    verifierName: verifierName, mocks: mocks)

proc newLeakedInteractionDefect*(threadId: int,
    site: tuple[filename: string, line: int, column: int]): ref LeakedInteractionDefect =
  let msg = "TRM fired on thread " & $threadId & " with no active verifier " &
    "at " & site.filename & ":" & $site.line & FFIScopeFooter
  result = (ref LeakedInteractionDefect)(msg: msg, threadId: threadId)

proc newPostTestInteractionDefect*(verifierName: string, generation: int,
    pluginName, procName: string): ref PostTestInteractionDefect =
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

proc newUnmockableContainerDefect*(procName, containerType: string,
    site: tuple[filename: string, line: int, column: int]): ref UnmockableContainerDefect =
  let msg = "unmockable container type '" & containerType &
    "' passed to " & procName & " at " & site.filename & ":" &
    $site.line & FFIScopeFooter
  result = (ref UnmockableContainerDefect)(msg: msg,
    procName: procName, containerType: containerType,
    site: (file: site.filename, line: site.line, column: site.column))
