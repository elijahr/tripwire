## nimfoot/errors.nim — full Defect hierarchy + constructors.
##
## Two roots descending from system:
##   NimfootDefect -> Defect       (verification failures; unswallowable)
##   NimfootError  -> CatchableError (API misuse; recoverable)

import std/tables
import ./types

type
  NimfootDefect* = object of Defect

  UnmockedInteractionDefect* = object of NimfootDefect
    pluginName*: string
    procName*: string
    fingerprint*: string
    args*: OrderedTable[string, string]
    site*: tuple[file: string, line, column: int]
    nearestMockHints*: seq[string]

  UnassertedInteractionsDefect* = object of NimfootDefect
    interactions*: seq[Interaction]
    verifierName*: string

  UnusedMocksDefect* = object of NimfootDefect
    mocks*: seq[Mock]
    verifierName*: string

  LeakedInteractionDefect* = object of NimfootDefect
    threadId*: int
    procName*: string

  PostTestInteractionDefect* = object of NimfootDefect
    verifierName*: string
    generation*: int
    pluginName*: string
    procName*: string

  PendingAsyncDefect* = object of NimfootDefect
    testName*: string

  UnmockableContainerDefect* = object of NimfootDefect
    procName*: string
    containerType*: string
    site*: tuple[file: string, line, column: int]

  NimfootError* = object of CatchableError

  AssertionInsideSandboxError* = object of NimfootError
    site*: tuple[file: string, line, column: int]

const FFIScopeFooter* = "\n(nimfoot intercepts Nim source calls only. " &
  "FFI ({.importc.}, {.dynlib.}, {.header.}) is not intercepted in v0. " &
  "See docs/concepts.md#scope.)"

# ---- Constructors --------------------------------------------------------

proc newUnmockedInteractionDefect*(pluginName, procName, fingerprint: string,
    site: tuple[file: string, line, column: int]): ref UnmockedInteractionDefect =
  let msg = "unmocked interaction: " & pluginName & "." & procName &
    " at " & site.file & ":" & $site.line & ":" & $site.column &
    "\n  fingerprint: " & fingerprint & FFIScopeFooter
  result = (ref UnmockedInteractionDefect)(msg: msg,
    pluginName: pluginName, procName: procName, fingerprint: fingerprint,
    site: site)

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
    "\nUse `waitFor` to drain futures, or -d:nimfootAllowPendingAsync to" &
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
