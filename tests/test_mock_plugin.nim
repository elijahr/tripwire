## tests/test_mock_plugin.nim — F1: MockPlugin type + registration.
import std/unittest
import nimfoot/[types, registry, intercept]
import nimfoot/plugins/mock

suite "MockPlugin":
  test "registered as 'mock' and enabled":
    let p = pluginByName("mock")
    check p != nil
    check p.enabled

  test "MockUserResponse[int] realizes the int":
    let r = MockUserResponse[int](returnValue: 42)
    check r.realize() == 42

  test "MockUserResponse[string] realizes the string":
    let r = MockUserResponse[string](returnValue: "hi")
    check r.realize() == "hi"

  test "supportsPassthrough is true":
    check mockPluginInstance.supportsPassthrough() == true

  test "passthroughFor is true for any name":
    check mockPluginInstance.passthroughFor("anything") == true
