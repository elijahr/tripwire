import std/[unittest, tables, deques, monotimes]
import nimfoot/types

suite "types":
  test "Plugin base type initializes with default values":
    let p = Plugin(name: "test", enabled: true)
    check p.name == "test"
    check p.enabled == true

  test "newMock returns a populated Mock":
    let resp = MockResponse()
    let m = newMock("proc1", "fp1", resp, (filename: "x.nim", line: 10, column: 3))
    check m.procName == "proc1"
    check m.argFingerprint == "fp1"
    check m.response == resp
    check m.site.file == "x.nim"
    check m.site.line == 10
    check m.site.column == 3

  test "Timeline default-initializes empty":
    var t = Timeline()
    check t.nextSeq == 0
    check t.entries.len == 0

  test "MockQueue default initializes with empty deque":
    var q = MockQueue(mocks: initDeque[Mock]())
    check q.mocks.len == 0
