## tripwire/types.nim — base types shared by every module.
##
## This module has NO dependencies on other tripwire modules and is
## safe to import from plugin authors and from the core.

import std/[tables, deques, monotimes]

type
  Plugin* = ref object of RootObj
    name*: string
    enabled*: bool

  MockResponse* = ref object of RootObj
    ## Base class. Each plugin subclasses this with concrete response
    ## fields (e.g. HttpMockResponse carries status/body/headers).

  Mock* = ref object
    procName*: string
    argFingerprint*: string
    response*: MockResponse
    site*: tuple[file: string, line, column: int]

  MockQueue* = object
    mocks*: Deque[Mock]

  InteractionKind* = enum
    ## Kinds of recorded interactions.
    ##
    ## - `ikMockMatched`: the call matched a registered mock (or a
    ##   plugin-recorded passthrough that the user is expected to
    ##   assert via DSLs like `responded()` / `assertMock`). Subject to
    ##   Guarantee 2 — must be marked asserted before sandbox teardown
    ##   or `UnassertedInteractionsDefect` fires.
    ## - `ikFirewallPassthrough`: the call was authorized by the
    ##   per-sandbox firewall (a matching `allow` / `restrict` predicate)
    ##   and passed through to the real implementation. The user's
    ##   `allow(plugin, M(...))` IS the assertion — Guarantee 2 SKIPS
    ##   these entries. Eliminates the per-test boilerplate
    ##   `for entry in v.timeline.entries: v.timeline.markAsserted(entry)`
    ##   that every firewall passthrough test would otherwise need.
    ikMockMatched
    ikFirewallPassthrough

  Interaction* = ref object
    sequence*: int
    plugin*: Plugin
    procName*: string
    args*: OrderedTable[string, string]
    response*: MockResponse
    asserted*: bool
    kind*: InteractionKind
    site*: tuple[file: string, line, column: int]
    createdAt*: MonoTime

  Timeline* = object
    entries*: seq[Interaction]
    nextSeq*: int

  AssertionContext* = object
    inAnyOrderActive*: bool
    strict*: bool

proc newMock*(procName, argFingerprint: string, response: MockResponse,
              site: tuple[filename: string, line: int, column: int]): Mock =
  ## Construct a Mock. The `site` argument uses `instantiationInfo()`'s
  ## tuple shape so call sites pass it directly.
  Mock(procName: procName, argFingerprint: argFingerprint,
       response: response,
       site: (file: site.filename, line: site.line, column: site.column))
