## tripwire/timeline.nim — Timeline and Interaction operations.
import std/[tables, monotimes]
import ./types

proc record*(t: var Timeline, plugin: Plugin, procName: string,
             args: OrderedTable[string, string], response: MockResponse,
             site: tuple[file: string, line, column: int]): Interaction {.raises: [].} =
  result = Interaction(
    sequence: t.nextSeq, plugin: plugin, procName: procName,
    args: args, response: response, asserted: false,
    site: site, createdAt: getMonoTime())
  inc(t.nextSeq)
  t.entries.add(result)

iterator unasserted*(t: Timeline): Interaction =
  for e in t.entries:
    if not e.asserted: yield e

proc markAsserted*(t: var Timeline, i: Interaction) =
  i.asserted = true
