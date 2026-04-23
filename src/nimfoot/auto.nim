## nimfoot/auto.nim — umbrella TRM module (Task G1).
##
## This module is the activation gateway for nimfoot. Consumer projects
## inject it into every test compilation unit via their test config.nims:
##
## ```nim
## --import:"nimfoot/auto"
## --define:"nimfootActive"
## ```
##
## The `--import` flag causes Nim to add `import nimfoot/auto` to every
## translation unit, which transitively imports every plugin module.
## Each plugin's module-init code calls `registerPlugin(...)` against
## the global registry, and their TRM templates become in-scope for
## pattern matching across the TU.
##
## Gated by `-d:nimfootActive`: when the define is absent, this module
## compiles to a no-op. This lets nimfoot modules be referenced in a
## project without accidentally activating TRM emission (e.g., when
## tooling parses the source tree without the test-config flags).
##
## See design doc §5 (activation model) and §10 Defense 1 (the facade
## guards `import nimfoot` with a compile-time error when `nimfootActive`
## is absent, pointing users at this umbrella).
when defined(nimfootActive):
  # Importing the plugin modules is sufficient: each plugin's module-init
  # code runs `registerPlugin(...)` against the global registry, and the
  # plugin's TRM templates become in-scope in every TU that has this
  # umbrella in its import graph (which is every TU when Nim's
  # `--import:"nimfoot/auto"` flag is set). No `export` is needed here —
  # and explicitly re-exporting the plugin modules would cause plugin
  # internals (e.g. `popMatchingMock` via `nimfootPluginIntercept`) to
  # resolve against any other TU that has an unrelated `import nimfoot/auto`
  # on its import path but does not directly import the core modules.
  import ./plugins/mock
  import ./plugins/httpclient
  import ./plugins/osproc
else:
  discard
