import std/[unittest, tables]
import tripwire/[types, timeline]

suite "timeline":
  test "record increments nextSeq and appends":
    var t = Timeline(nextSeq: 0)
    let p = Plugin(name: "p1")
    let args = initOrderedTable[string, string]()
    let i = t.record(p, "f", args, nil, (file: "x", line: 1, column: 0))
    check t.nextSeq == 1
    check t.entries.len == 1
    check i.sequence == 0
    check i.procName == "f"
    check i.asserted == false

  test "unasserted iterator yields only unasserted":
    var t = Timeline(nextSeq: 0)
    let p = Plugin(name: "p1")
    let args = initOrderedTable[string, string]()
    let i1 = t.record(p, "f1", args, nil, (file: "x", line: 1, column: 0))
    let i2 = t.record(p, "f2", args, nil, (file: "x", line: 2, column: 0))
    t.markAsserted(i1)
    discard i2
    var pending: seq[string]
    for e in t.unasserted: pending.add(e.procName)
    check pending == @["f2"]

  test "value-in-ref mutation via field access (regression for §4.1 note)":
    ## This verifies that given `v: ref object containing Timeline`,
    ## passing `v.timeline` to a `var Timeline` parameter works. Nim
    ## makes `v.timeline` an lvalue because v is a ref.
    type Carrier = ref object
      timeline: Timeline
    var c = Carrier(timeline: Timeline(nextSeq: 0))
    let p = Plugin(name: "p1")
    let args = initOrderedTable[string, string]()
    discard c.timeline.record(p, "f", args, nil, (file: "x", line: 1, column: 0))
    check c.timeline.nextSeq == 1
    check c.timeline.entries.len == 1
