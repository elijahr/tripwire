## tripwire/verify.nim — mock registration, popMatchingMock, verifyAll,
## fingerprint helpers.
import std/[tables, deques, options]
import ./[types, timeline, sandbox, errors]

proc registerMock*(v: Verifier, pluginName: string, m: Mock) =
  if pluginName notin v.mockQueues:
    v.mockQueues[pluginName] = MockQueue(mocks: initDeque[Mock]())
  v.mockQueues[pluginName].mocks.addLast(m)

proc popMatchingMock*(v: Verifier, pluginName, procName,
                     fingerprint: string): Option[Mock] =
  if pluginName notin v.mockQueues: return none(Mock)
  # Take mutable reference via table access; field assignment persists
  # because Table[string, MockQueue] holds MockQueue by value but MockQueue
  # carries a Deque[Mock] (ref-backed).
  if v.mockQueues[pluginName].mocks.len == 0: return none(Mock)
  let head = v.mockQueues[pluginName].mocks[0]
  if head.procName == procName and head.argFingerprint == fingerprint:
    return some(v.mockQueues[pluginName].mocks.popFirst())
  if v.context.inAnyOrderActive:
    let q = v.mockQueues[pluginName]
    for i in 0 ..< q.mocks.len:
      if q.mocks[i].procName == procName and
         q.mocks[i].argFingerprint == fingerprint:
        # Capture BEFORE mutating the deque (§4.1 regression guard).
        let matched = q.mocks[i]
        var tmp: seq[Mock]
        for j in 0 ..< q.mocks.len:
          if j != i: tmp.add(q.mocks[j])
        v.mockQueues[pluginName].mocks.clear()
        for mm in tmp: v.mockQueues[pluginName].mocks.addLast(mm)
        return some(matched)
  none(Mock)

proc verifyAll*(v: Verifier) =
  ## Check the three guarantees. Raises the FIRST violation.
  # Guarantee 2: every recorded interaction explicitly asserted.
  var unasserted: seq[Interaction] = @[]
  for i in v.timeline.unasserted: unasserted.add(i)
  if unasserted.len > 0:
    raise newUnassertedInteractionsDefect(v.name, unasserted)
  # Guarantee 3: every registered mock consumed.
  var unusedMocks: seq[Mock] = @[]
  for pluginName, q in v.mockQueues.pairs:
    for m in q.mocks: unusedMocks.add(m)
  if unusedMocks.len > 0:
    raise newUnusedMocksDefect(v.name, unusedMocks)
  # Guarantee 1 is raised eagerly by TRM bodies; nothing to do here.

proc fingerprintOf*(procName: string, renderedArgs: seq[string]): string =
  ## Deterministic canonicalization. Format: procName|arg0|arg1|...
  result = procName
  for a in renderedArgs:
    result.add('|')
    result.add(a)
