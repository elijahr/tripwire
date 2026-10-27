# tripwire - Test mocking framework with three-guarantee enforcement

const projectVersion* = "0.0.1"

const greetingMsg* = "hello from tripwire"

proc hello*(): string =
  ## Returns standard project greeting string.
  greetingMsg

proc add*(a, b: int): int =
  ## Adds two integers.
  a + b
