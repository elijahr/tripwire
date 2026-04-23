import std/[unittest, tables, strutils]
import tripwire/[types, errors, plugin_base]

suite "plugin base methods":
  test "default assertableFields is empty seq":
    let p = Plugin(name: "x", enabled: true)
    let i = Interaction(plugin: p, procName: "f")
    check p.assertableFields(i) == newSeq[string]()

  test "default formatInteraction emits '<plugin> <proc>'":
    let p = Plugin(name: "httpclient", enabled: true)
    let i = Interaction(plugin: p, procName: "request")
    check p.formatInteraction(i) == "httpclient request"

  test "default formatError emits '<kind> in <plugin>.<proc>'":
    let p = Plugin(name: "httpclient", enabled: true)
    let i = Interaction(plugin: p, procName: "request")
    check p.formatError(i, "unmocked") == "unmocked in httpclient.request"

  test "default matches returns true":
    let p = Plugin(name: "x", enabled: true)
    let i = Interaction(plugin: p, procName: "f")
    let empty = initOrderedTable[string, string]()
    check p.matches(i, empty) == true

  test "newUnmockedInteractionDefect message uses formatInteraction":
    # The upgraded errors message should include `<plugin> <proc>` from
    # formatInteraction rather than a raw procName-only rendering.
    let e = newUnmockedInteractionDefect("httpclient", "request", "fp",
      (file: "t.nim", line: 1, column: 1))
    check "httpclient" in e.msg
    check "request" in e.msg
