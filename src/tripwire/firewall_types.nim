## tripwire/firewall_types.nim - neutral home for FirewallMode and
## fingerprint-token escape helpers.
##
## Hosts FirewallMode here so both sandbox.nim and config.nim can import
## it without creating a sandbox<->config import cycle. Imports nothing
## else from tripwire to keep the dependency graph acyclic.
##
## Also hosts `escapeFingerprintField` so every plugin that builds a
## typed-token fingerprint string can sanitize user-supplied values
## (path, query) without each plugin pulling in `sandbox` (which would
## create a cycle).

type
  FirewallMode* = enum
    ## Disposition of unmocked-and-not-allowed calls.
    ##
    ## Used in two contexts:
    ##   * Per-Verifier (`Verifier.firewallMode`): inside-sandbox unmocked-call
    ##     disposition. `fmError` raises UnmockedInteractionDefect; `fmWarn`
    ##     emits a stderr warning and proceeds via passthrough.
    ##   * Project-wide (`FirewallConfig.guard`): outside-sandbox disposition
    ##     for unmocked TRM calls. `fmError` raises LeakedInteractionDefect;
    ##     `fmWarn` either passes through (plugin supports it) or raises
    ##     OutsideSandboxNoPassthroughDefect (plugin doesn't).
    ##
    ## Defaults to `fmError` in both contexts to preserve "every external call
    ## is pre-authorized" without explicit opt-in.
    fmError, fmWarn

proc escapeFingerprintField*(s: string): string {.raises: [].} =
  ## Make `s` safe to embed as a single whitespace-delimited token in a
  ## typed-token fingerprint string (the `key=value` format consumed by
  ## `sandbox.matchesFingerprint`). Replaces any ASCII-whitespace
  ## character with its percent-encoded equivalent so
  ## `sandbox.tokenizeMatcherHead` cannot split the value mid-field.
  ##
  ## Why: `parseUri` on a URL like `http://host/path with space` yields
  ## a `path` field containing a literal space. Embedding that path
  ## verbatim into the fingerprint would let the tokenizer split it,
  ## producing tokens like `path=path` and `with` and `space`, which
  ## would cause the per-field anchored match to either miss valid
  ## inputs or (worse) accidentally match an unrelated subsequent
  ## field. Same risk applies to the `query=` token.
  ##
  ## The replacement set covers ASCII whitespace (` `, `\t`, `\n`,
  ## `\r`). It is idempotent on already-encoded inputs (a literal
  ## `%20` passes through unchanged because `%` is not whitespace), so
  ## a path that round-tripped through a properly-encoded URL is
  ## unaffected.
  ##
  ## Fast path: this proc runs on every intercepted interaction
  ## (path/query of every URL, every header), and the overwhelming
  ## majority of values contain no ASCII whitespace. Scan once and
  ## return the input unchanged when no escaping is needed — that
  ## avoids the per-character allocation/copy and keeps the hot path
  ## allocation-free in the common case.
  var needsEscape = false
  for c in s:
    if c in {' ', '\t', '\n', '\r'}:
      needsEscape = true
      break
  if not needsEscape: return s
  result = newStringOfCap(s.len + 4)
  for c in s:
    case c
    of ' ':  result.add("%20")
    of '\t': result.add("%09")
    of '\n': result.add("%0A")
    of '\r': result.add("%0D")
    else:    result.add(c)
