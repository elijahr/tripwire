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

  Interaction* = ref object
    sequence*: int
    plugin*: Plugin
    procName*: string
    args*: OrderedTable[string, string]
    response*: MockResponse
    asserted*: bool
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
