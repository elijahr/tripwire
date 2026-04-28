## tripwire/sandbox.nim — Verifier type, thread-local stack, sandbox template,
## firewall API (`allow` / `restrict` / matchers).
##
## Firewall vocabulary (modeled on axiomantic/bigfoot, the Python library
## tripwire ports):
##
##   * `sandbox.allow(plugin)`              — ALL calls intercepted by `plugin`
##                                            may fall through to the real impl.
##   * `sandbox.allow(plugin, predicate)`   — closure escape hatch:
##                                            `proc(procName, fp: string): bool`.
##   * `sandbox.allow(plugin, M(host = "127.0.0.1"))`
##                                          — matcher DSL; plugins receive the
##                                            Matcher via `AllowMatch` and SHOULD
##                                            honor host/port/method/path.
##   * `sandbox.restrict(...)`              — ceiling on `allow`. Bigfoot's
##                                            mental model: `allow` lists what
##                                            the sandbox PERMITS; `restrict`
##                                            shrinks the permission set down to
##                                            what falls inside the ceiling. A
##                                            `restrict` entry alone authorizes
##                                            nothing — it filters allows, it
##                                            does not grant.
##   * `firewallMode` on the Verifier        — `fmError` (default; tripwire's
##                                            three-guarantees posture) raises
##                                            `UnmockedInteractionDefect` for
##                                            unmocked-and-not-allowed calls;
##                                            `fmWarn` writes a one-line warning
##                                            to stderr and proceeds via
##                                            passthrough.
##
## ## Ceiling semantics
##
## `restrict` is a ceiling on the sandbox's effective permission set. The
## decision rule is observationally:
##
##   * If `restrict` is empty for a plugin: the call passes iff some `allow`
##     entry for that plugin matches.
##   * If `restrict` is non-empty for a plugin: the call passes iff some
##     `allow` entry matches AND some `restrict` entry matches.
##
## This is equivalent to "intersect allow with restrict at call time": the
## predicates aren't enumerable sets, so the intersection is computed by
## checking both sides against the live call. The most useful pattern is a
## broad `allow(plugin)` (blanket: matches every call) narrowed by a
## `restrict(plugin, M(...))` ceiling — say "permit anything httpclient
## intercepts, but only for hosts under 127.0.0.*."
##
## Tripwire today has a single (flat) sandbox scope. When nested sandboxes
## land in a future release, the ceiling extends naturally: an inner
## `restrict` filters the union of outer + inner allows, so an inner block
## can only TIGHTEN the ceiling, never widen it (bigfoot's "inner blocks
## cannot widen" guarantee).
##
## Consultation order in the intercept combinators
## (`tripwire/intercept.tripwireInterceptBody`,
## `tripwire/plugins/plugin_intercept.tripwirePluginIntercept`):
##
##   1. Mock match → return mock response.
##   2. Plugin's own `passthroughFor(procName)` (e.g., MockPlugin's blanket).
##      This is a tripwire-specific extension that sits above the firewall;
##      the per-plugin gate is consulted before allow/restrict.
##   3. If any `allow` entry matches AND (if `restrict` is non-empty) some
##      `restrict` entry also matches → spy body runs.
##   4. Otherwise → defect/warn (per `firewallMode`).
import std/[tables, monotimes, strutils]
import ./[types, timeline, errors, plugin_base, firewall_types]
import ./async_registry_types

export firewall_types

type
  Matcher* = object
    ## Plugin-readable allow/restrict predicate descriptor. Optional
    ## fields are empty strings / -1 / etc. when unset; plugins SHOULD
    ## honor the fields they understand and ignore the rest.
    ##
    ## String fields support glob-style wildcards: `*` matches zero or
    ## more characters, `?` matches exactly one. `*.example.com` and
    ## `127.0.0.*` are the load-bearing forms — kept simple; no regex.
    host*: string
    port*: int      ## -1 = unset
    httpMethod*: string
    path*: string
    scheme*: string
    procName*: string  ## optional: gate by intercepted procName

  AllowPredicate* = proc(procName, fingerprint: string): bool {.
                         closure, gcsafe, raises: [].}
    ## Closure-escape-hatch firewall predicate. Use when matchers don't
    ## express the policy you need — e.g. fingerprint substring tests,
    ## counters, file-state probes.
    ##
    ## `raises: []` is load-bearing: the predicate is consulted from the
    ## firewall hot path, which itself sits inside TRM expansions that
    ## may sit inside chronos `async: (raises: [...])` procs. A
    ## predicate that could raise CatchableError would push that effect
    ## into the surrounding strict-raises proc and break compilation.
    ## Predicates with side-effecting probes (counters, file-state)
    ## must catch their own exceptions internally.

  AllowEntryKind* = enum
    aekAllPlugin, aekPredicate, aekMatcher

  AllowEntry* = object
    plugin*: Plugin
    case kind*: AllowEntryKind
    of aekPredicate:
      predicate*: AllowPredicate
    of aekMatcher:
      matcher*: Matcher
    of aekAllPlugin:
      discard ## blanket: any call routed through this plugin is allowed

  Verifier* = ref object
    name*: string
    timeline*: Timeline
    mockQueues*: Table[string, MockQueue]
    context*: AssertionContext
    generation*: int
    createdAt*: MonoTime
    active*: bool
    futureRegistry*: seq[RegisteredFuture]
    allowPredicates*: seq[AllowEntry]
      ## Per-sandbox `allow` entries. Lifetime is bounded by the
      ## verifier: pushed in `sandbox:` template, freed when the
      ## verifier is popped. Consulted by `tripwirePluginIntercept`
      ## (and `tripwireInterceptBody`) when a call has no mock and
      ## the plugin's own `passthroughFor` says no.
    restrictPredicates*: seq[AllowEntry]
      ## Per-sandbox `restrict` entries — the ceiling on `allow`. When
      ## non-empty for a given plugin, the effective permission set is
      ## the intersection of `allowPredicates` and `restrictPredicates`
      ## for that plugin: a call passes iff some `allow` entry matches
      ## AND some `restrict` entry matches. With no `allow` registered,
      ## a non-empty `restrict` authorizes nothing (the intersection is
      ## empty). See module docstring for the full ceiling semantics.
    firewallMode*: FirewallMode

proc newVerifier*(name: string = ""): Verifier =
  Verifier(name: name, timeline: Timeline(nextSeq: 0),
           mockQueues: initTable[string, MockQueue](),
           context: AssertionContext(strict: true),
           generation: 0, createdAt: getMonoTime(), active: true,
           allowPredicates: @[], restrictPredicates: @[],
           firewallMode: fmError)

var verifierStack* {.threadvar.}: seq[Verifier]

proc pushVerifier*(v: Verifier): Verifier =
  verifierStack.add(v)
  v

proc popVerifier*(): Verifier =
  doAssert verifierStack.len > 0, "popVerifier called on empty stack"
  result = verifierStack.pop()
  inc(result.generation)
  result.active = false

proc currentVerifier*(): Verifier {.inline, raises: [].} =
  if verifierStack.len == 0: nil else: verifierStack[^1]

# ---- Matcher DSL ---------------------------------------------------------

proc initMatcher*(host = ""; port = -1; httpMethod = ""; path = "";
                  scheme = ""; procName = ""): Matcher =
  ## Construct a Matcher. Direct callers may use this; the `M(...)`
  ## template is the keyword-arg-friendly façade most call sites should
  ## reach for.
  Matcher(host: host, port: port, httpMethod: httpMethod, path: path,
          scheme: scheme, procName: procName)

template M*(args: varargs[untyped]): Matcher =
  ## Keyword-arg matcher constructor. Mirrors bigfoot's `M(...)`. Only
  ## the named fields you supply are populated; everything else stays
  ## unset (empty string / -1).
  ##
  ## Example: `sandbox.allow(httpclientPlugin, M(host = "*.example.com",
  ##                                              httpMethod = "GET"))`
  initMatcher(args)

proc globMatch*(pat, s: string): bool {.raises: [].} =
  ## Glob match: `*` zero-or-more, `?` exactly one. Anchored start +
  ## end. Linear-scan with single-segment backtracking; sufficient for
  ## host/path patterns. No regex dep.
  if pat.len == 0: return s.len == 0
  var pi, si, starPi, starSi = 0
  starPi = -1
  while si < s.len:
    if pi < pat.len and (pat[pi] == '?' or pat[pi] == s[si]):
      inc pi; inc si
    elif pi < pat.len and pat[pi] == '*':
      starPi = pi
      starSi = si
      inc pi
    elif starPi != -1:
      pi = starPi + 1
      inc starSi
      si = starSi
    else:
      return false
  while pi < pat.len and pat[pi] == '*':
    inc pi
  pi == pat.len

proc tokenizeMatcherHead*(fingerprint: string): seq[string] {.raises: [].} =
  ## Split the matcher-relevant prefix of the fingerprint on whitespace.
  ## Body content (and `hdr=`/`mp=` after it) can contain whitespace
  ## that would otherwise inflate the token list and cost per-decision
  ## allocations.
  ##
  ## Implementation: locate the ` body=` separator with a single
  ## `find` call (memchr-style scan), then split only the head slice.
  ## This avoids producing seq-yielded sub-strings for every space
  ## inside the body content under the iterator, even though the
  ## previous loop-and-break shape did short-circuit yielding once
  ## `body=` was reached — `find` performs the scan in one allocation-
  ## free pass and the head slice is a tighter input to `split`.
  ##
  ## Anchoring at `body=` is safe because every HTTP-shape fingerprint
  ## builder (`fingerprintHttpRequest`, `fingerprintChronosSend` etc.)
  ## emits the matcher-relevant fields (method/scheme/host/port/path/
  ## query) BEFORE `body=`, and the Matcher type only consults those
  ## fields. Non-HTTP fingerprints (mock/osproc `fingerprintOf`) have
  ## no ` body=` substring, so `find` returns -1 and the entire
  ## fingerprint is split — cheap because those fingerprints are
  ## short and have no `key=value`-shaped tokens, so per-field lookups
  ## return "not found" anyway.
  let bodyIdx = fingerprint.find(" body=")
  let head =
    if bodyIdx >= 0: fingerprint.substr(0, bodyIdx - 1)
    else: fingerprint
  result = head.split(' ')

proc tokenValueRef(tokens: openArray[string], prefix: string):
    tuple[found: bool, tok: int, valueStart: int]
    {.inline, raises: [].} =
  ## Locate the FIRST whitespace-delimited token that starts with
  ## `<prefix>` and return the index of that token plus the byte
  ## offset where the value (substring after `<prefix>`) begins.
  ## Returning a `(tok, offset)` pair instead of a sliced
  ## `tok[prefix.len .. ^1]` substring lets callers compare the
  ## value against a matcher field WITHOUT allocating a fresh
  ## string per field per matcher per intercepted call.
  for i, tok in tokens:
    if tok.len >= prefix.len and tok.startsWith(prefix):
      return (true, i, prefix.len)
  (false, -1, 0)

proc equalsAt(tok: string; start: int; s: string): bool
    {.inline, raises: [].} =
  ## Compare `s` against the substring `tok[start .. ^1]` in-place.
  ## Equivalent to `tok[start .. ^1] == s` but does not allocate.
  if tok.len - start != s.len: return false
  for i in 0 ..< s.len:
    if tok[start + i] != s[i]: return false
  true

proc globMatchAt(pat: string; s: string; sStart: int): bool
    {.inline, raises: [].} =
  ## Glob match where `s` is treated as starting at byte `sStart`.
  ## Mirrors the structure of `globMatch` exactly; only differs in
  ## that `si` and `starSi` index from `sStart` instead of 0. Used
  ## by the firewall hot path to glob-match a matcher pattern
  ## against `tok[valueStart .. ^1]` without allocating the slice.
  if pat.len == 0: return sStart == s.len
  var pi = 0
  var si = sStart
  var starPi = -1
  var starSi = sStart
  while si < s.len:
    if pi < pat.len and (pat[pi] == '?' or pat[pi] == s[si]):
      inc pi; inc si
    elif pi < pat.len and pat[pi] == '*':
      starPi = pi
      starSi = si
      inc pi
    elif starPi != -1:
      pi = starPi + 1
      inc starSi
      si = starSi
    else:
      return false
  while pi < pat.len and pat[pi] == '*':
    inc pi
  pi == pat.len

proc fieldHitsTokens(field: string;
                     tokens: openArray[string]; prefix: string): bool {.
    inline, raises: [].} =
  ## Anchored typed-token match. Looks up the `prefix=` token in the
  ## already-tokenized fingerprint and matches `field` against the
  ## value-after-`=` (glob if wildcards, equality otherwise).
  ##
  ## Token-anchored match is load-bearing for firewall safety: the
  ## previous "any whitespace-token equals field" rule produced
  ## false positives whenever the fingerprint contained the literal
  ## string anywhere (e.g., a query value `?target=127.0.0.1`
  ## spuriously matched `M(host="127.0.0.1")`). Anchoring to
  ## `host=`, `port=`, etc. eliminates that class.
  ##
  ## Allocation note: uses the `*Ref` / `*At` helpers so the
  ## per-field/per-matcher hot path does NOT allocate a sliced
  ## value string.
  let (found, tokIdx, valueStart) = tokenValueRef(tokens, prefix)
  if not found: return false
  if "*" in field or "?" in field:
    globMatchAt(field, tokens[tokIdx], valueStart)
  else:
    equalsAt(tokens[tokIdx], valueStart, field)

proc pathHitsTokens(pattern: string;
                    tokens: openArray[string]): bool {.inline, raises: [].} =
  ## Anchored path match. `path=<value>` is a single token under the
  ## new typed format, so `path` is treated like host/port/scheme/method
  ## (anchor on `path=` and match the value). The legacy "unanchored
  ## glob across the whole fingerprint" semantics are gone — they were
  ## a workaround for the path containing `/` characters that the old
  ## token split shredded. Without wildcards, equality on the value;
  ## with wildcards, glob against the value.
  let (found, tokIdx, valueStart) = tokenValueRef(tokens, "path=")
  if not found: return false
  if "*" in pattern or "?" in pattern:
    globMatchAt(pattern, tokens[tokIdx], valueStart)
  else:
    equalsAt(tokens[tokIdx], valueStart, pattern)

proc matchesFingerprintTokens*(m: Matcher, procName: string,
                                tokens: openArray[string]): bool {.raises: [].} =
  ## Pre-tokenized variant. The firewall hot loop (`sandboxAllowsFor` /
  ## `sandboxRestrictsFor`) tokenizes the fingerprint ONCE per call and
  ## reuses the resulting `seq[string]` across every Matcher entry,
  ## avoiding O(N_matchers · split) work on sandboxes with many rules.
  ##
  ## Callers MUST have already short-circuited the procName check and
  ## the no-fields-set fast path; this proc assumes both have been
  ## handled by the caller (`matchesFingerprint` does this before
  ## delegating).
  if m.host.len > 0 and not fieldHitsTokens(m.host, tokens, "host="):
    return false
  if m.httpMethod.len > 0 and
     not fieldHitsTokens(m.httpMethod, tokens, "method="):
    return false
  if m.path.len > 0 and not pathHitsTokens(m.path, tokens):
    return false
  if m.scheme.len > 0 and not fieldHitsTokens(m.scheme, tokens, "scheme="):
    return false
  if m.port >= 0 and not fieldHitsTokens($m.port, tokens, "port="):
    return false
  true

proc matchesFingerprint*(m: Matcher, procName,
                         fingerprint: string): bool {.raises: [].} =
  ## Default Matcher → fingerprint matcher.
  ##
  ## ## Fingerprint format
  ##
  ## HTTP-shape plugins (httpclient, chronos_httpclient, websock) emit
  ## fingerprints as a space-separated `key=value` token sequence:
  ##
  ##   `method=GET scheme=http host=127.0.0.1 port=80 path=/api ...`
  ##
  ## Matcher fields anchor on these typed keys: `host` looks for a
  ## `host=` token, `port` for a `port=` token, etc. The match is on
  ## the value after `=`.
  ##
  ## ## Field semantics (each independent; ALL set fields must match)
  ##
  ##   * `procName` (if set) — exact equality with the intercepted
  ##     proc name argument.
  ##   * `host`, `httpMethod`, `scheme`, `path` (if set) — anchored on
  ##     the corresponding `<key>=` token. Wildcards (`*`, `?`) trigger
  ##     glob match against the value; otherwise equality.
  ##   * `port` (if >= 0) — anchored on `port=`; value compared as a
  ##     stringified int (so `M(port=80)` cleanly rejects port 8080).
  ##
  ## ## Backward compatibility
  ##
  ## Non-HTTP plugins (mock, osproc) still use the generic
  ## `fingerprintOf(procName, args)` shape (`procName|arg0|arg1|...`).
  ## Such fingerprints have no `<key>=` tokens, so any set Matcher
  ## field returns false (the keyed token isn't found). Predicate-based
  ## `allow(plugin, proc(...))` is the escape hatch for non-HTTP
  ## fingerprints.
  ##
  ## ## Performance
  ##
  ## Tokenization happens ONCE at the top of this proc; field lookups
  ## then scan the cached `seq[string]`. Avoids re-splitting per field.
  if m.procName.len > 0 and m.procName != procName:
    return false
  # No Matcher field set → trivially matches (procName already checked).
  if m.host.len == 0 and m.httpMethod.len == 0 and m.path.len == 0 and
     m.scheme.len == 0 and m.port < 0:
    return true
  matchesFingerprintTokens(m, procName, tokenizeMatcherHead(fingerprint))

# ---- allow / restrict registration --------------------------------------

proc allow*(plugin: Plugin) =
  ## Plugin-name shorthand: any call intercepted by `plugin` falls
  ## through to its real implementation. Equivalent in spirit to
  ## bigfoot's `allow("dns")`.
  let v = currentVerifier()
  if v.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  v.allowPredicates.add(AllowEntry(plugin: plugin, kind: aekAllPlugin))

proc allow*(plugin: Plugin, predicate: AllowPredicate) =
  ## Closure-escape-hatch. Predicate receives `(procName, fingerprint)`
  ## and returns true to allow.
  let v = currentVerifier()
  if v.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  v.allowPredicates.add(AllowEntry(plugin: plugin, kind: aekPredicate,
                                   predicate: predicate))

proc allow*(plugin: Plugin, matcher: Matcher) =
  ## Matcher-DSL form. The matcher is consulted via
  ## `Matcher.matchesFingerprint(procName, fingerprint)`; plugin authors
  ## with structured call data SHOULD upgrade by parsing the
  ## fingerprint themselves before this lookup runs.
  let v = currentVerifier()
  if v.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  v.allowPredicates.add(AllowEntry(plugin: plugin, kind: aekMatcher,
                                   matcher: matcher))

proc restrict*(plugin: Plugin) =
  ## Ceiling-on-`allow`, plugin-name shorthand. A blanket `restrict`
  ## entry matches every call routed through `plugin`, so it narrows
  ## the ceiling to "anything for this plugin" — equivalent to no
  ## ceiling at all for `plugin` while still filtering OTHER plugins'
  ## allows down to nothing (any plugin without its own `restrict`
  ## entry has an empty ceiling and rejects). Mostly useful as a
  ## scaffold; structured matchers are the load-bearing form.
  let v = currentVerifier()
  if v.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  v.restrictPredicates.add(AllowEntry(plugin: plugin, kind: aekAllPlugin))

proc restrict*(plugin: Plugin, predicate: AllowPredicate) =
  ## Ceiling on `allow`. The predicate is consulted at call time; calls
  ## that don't match it are outside the ceiling and reject regardless
  ## of `allow`. With no matching `allow`, this still authorizes
  ## nothing — `restrict` filters the permission set, it does not grant.
  let v = currentVerifier()
  if v.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  v.restrictPredicates.add(AllowEntry(plugin: plugin, kind: aekPredicate,
                                      predicate: predicate))

proc restrict*(plugin: Plugin, matcher: Matcher) =
  ## Ceiling on `allow`, matcher-DSL form. The matcher is the canonical
  ## "narrow a broad allow" tool: pair `allow(plugin)` (blanket) with
  ## `restrict(plugin, M(host="..."))` (ceiling) to permit everything
  ## the plugin intercepts EXCEPT calls that fall outside the matcher.
  let v = currentVerifier()
  if v.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  v.restrictPredicates.add(AllowEntry(plugin: plugin, kind: aekMatcher,
                                      matcher: matcher))

# ---- Consultation helpers (used by intercept combinators) ---------------

proc entryMatchesTokens(entry: AllowEntry, plugin: Plugin,
                        procName, fingerprint: string;
                        tokens: openArray[string]): bool {.raises: [].} =
  ## Per-entry match, taking pre-tokenized fingerprint head so the
  ## caller's loop avoids re-splitting on every entry. Predicate-form
  ## entries still receive the raw fingerprint string (they may inspect
  ## body/hdr/mp content the matcher head doesn't capture).
  if entry.plugin != plugin:
    return false
  case entry.kind
  of aekAllPlugin:
    true
  of aekPredicate:
    entry.predicate(procName, fingerprint)
  of aekMatcher:
    # Inline the procName check + no-fields-set fast path here to
    # mirror what `matchesFingerprint` does before delegating, so the
    # tokens variant can be called directly without re-tokenizing.
    if entry.matcher.procName.len > 0 and
       entry.matcher.procName != procName:
      false
    elif entry.matcher.host.len == 0 and entry.matcher.httpMethod.len == 0 and
         entry.matcher.path.len == 0 and entry.matcher.scheme.len == 0 and
         entry.matcher.port < 0:
      true
    else:
      matchesFingerprintTokens(entry.matcher, procName, tokens)

proc entryMatches(entry: AllowEntry, plugin: Plugin,
                  procName, fingerprint: string): bool {.raises: [].} =
  ## Single-entry match for callers that have just one entry to check
  ## (or that haven't tokenized yet). Tokenizes lazily.
  entryMatchesTokens(entry, plugin, procName, fingerprint,
                     tokenizeMatcherHead(fingerprint))

proc sandboxAllowsForTokens(v: Verifier, plugin: Plugin,
                            procName, fingerprint: string,
                            tokens: seq[string]): bool {.raises: [].} =
  ## Internal tokens-already-computed variant. Lets `firewallDecideRaw`
  ## tokenize the fingerprint once and reuse those tokens across both
  ## the allow loop and the restrict loop, rather than tokenizing
  ## twice per intercepted call.
  if v.isNil: return false
  for entry in v.allowPredicates:
    if entry.entryMatchesTokens(plugin, procName, fingerprint, tokens):
      return true
  false

proc sandboxAllowsFor*(v: Verifier, plugin: Plugin,
                       procName, fingerprint: string): bool {.raises: [].} =
  ## OR over all per-sandbox `allow` entries registered against `plugin`
  ## (by ref identity). Returns `true` on the first match. Used by the
  ## TRM-body combinators to extend the existing
  ## `plugin.passthroughFor(procName)` gate with a per-sandbox,
  ## fingerprint-aware decision.
  ##
  ## Tokenizes the fingerprint ONCE for the entire predicate loop and
  ## reuses the tokens across every entry — relevant for sandboxes
  ## carrying many `allow`/`restrict` rules.
  if v.isNil: return false
  sandboxAllowsForTokens(v, plugin, procName, fingerprint,
                         tokenizeMatcherHead(fingerprint))

proc sandboxRestrictsForTokens(v: Verifier, plugin: Plugin,
                               procName, fingerprint: string,
                               tokens: seq[string]):
                               tuple[active: bool, allows: bool]
                               {.raises: [].} =
  ## Internal tokens-already-computed variant of `sandboxRestrictsFor`.
  ## See `sandboxAllowsForTokens` for rationale.
  if v.isNil or v.restrictPredicates.len == 0:
    return (active: false, allows: false)
  var hasRestrictionsForPlugin = false
  for entry in v.restrictPredicates:
    if entry.plugin == plugin:
      hasRestrictionsForPlugin = true
      if entry.entryMatchesTokens(plugin, procName, fingerprint, tokens):
        return (active: true, allows: true)
  (active: hasRestrictionsForPlugin, allows: false)

proc sandboxRestrictsFor*(v: Verifier, plugin: Plugin,
                          procName, fingerprint: string):
                          tuple[active: bool, allows: bool] {.raises: [].} =
  ## Computes the ceiling side of the firewall decision. The runtime
  ## decision (in `firewallDecideRaw`) is "allow ∩ restrict" at call
  ## time: passthrough requires a matching `allow` AND, if any
  ## `restrict` entries are configured FOR THIS PLUGIN, a matching
  ## `restrict`.
  ##
  ## Per-plugin scoping is load-bearing: a `restrict(httpclient, ...)`
  ## entry must NOT reject a call intercepted by `osproc`. The
  ## `active` flag therefore tracks whether any restrict entry exists
  ## *for this plugin specifically* — not whether the verifier has any
  ## restrict entries at all.
  ##
  ## Returns `(active, allows)`:
  ##   - `active = false` means no `restrict` entry targets this plugin;
  ##     the ceiling is open for this plugin, so the decision reduces
  ##     to "does some allow match?".
  ##   - `active = true, allows = true` means at least one `restrict`
  ##     entry for this plugin matched `(procName, fingerprint)`; the
  ##     ceiling admits this call.
  ##   - `active = true, allows = false` means restrict is configured
  ##     for this plugin but no entry matches — the ceiling rejects
  ##     regardless of `allow`. With no `allow` registered the ceiling
  ##     also rejects (the intersection of empty allow with anything
  ##     is empty).
  sandboxRestrictsForTokens(v, plugin, procName, fingerprint,
                            tokenizeMatcherHead(fingerprint))

# ---- Firewall mode helpers ----------------------------------------------

proc guard*(v: Verifier, mode: FirewallMode) =
  ## Set firewall mode on a verifier (also reachable as
  ## `currentVerifier().firewallMode = ...`). The `guard=` form is the
  ## bigfoot-aligned spelling for in-test toggles.
  if v.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  v.firewallMode = mode

proc emitFirewallWarning*(pluginName, procName,
                          fingerprint: string) {.raises: [].} =
  ## Stderr write for `fmWarn` mode. Single-line, prefix-stable so
  ## consumers can grep / filter. Called by the intercept combinators
  ## just before they fall through to `spyBody`.
  ##
  ## Annotated `{.raises: [].}` because the TRM expansion site may sit
  ## inside a strict-raises consumer (e.g., a chronos
  ## `async: (raises: [HttpError])` proc). `stderr.writeLine` raises
  ## `IOError`; we suppress it because losing a single firewall warning
  ## on a stderr write failure is preferable to propagating an
  ## unmodelled CatchableError out of the hot path. Stderr write
  ## failures are vanishingly rare in practice (no disk involved).
  try:
    stderr.writeLine "tripwire firewall: warn passthrough for " &
      pluginName & "." & procName & " (fp=" & fingerprint & ")"
  except IOError:
    discard

type FirewallDecision* = enum
  fdAllow, fdWarn, fdRaise

proc firewallDecideRaw*(v: Verifier, plugin: Plugin, procName,
                        fingerprint: string): FirewallDecision {.raises: [].} =
  ## Pure decision proc — exposed for unit tests and plugin authors
  ## writing custom intercept combinators. Side-effect-free.
  ##
  ## Decision rule (bigfoot ceiling model in flat-scope semantics):
  ##
  ##   1. Plugin-level blanket passthrough (e.g., MockPlugin's
  ##      `passthroughFor` over every procName) → fdAllow. This is a
  ##      tripwire-specific extension that sits above the firewall.
  ##   2. Compute the ceiling: if `restrict` is non-empty for `plugin`
  ##      and no `restrict` entry matches the call, the call is OUTSIDE
  ##      the ceiling → fdRaise (or fdWarn).
  ##   3. Otherwise the call is inside (or there is no) ceiling.
  ##      Consult `allow`: if some entry matches → fdAllow.
  ##   4. No allow match → fdRaise (or fdWarn).
  ##
  ## Steps 2-3 jointly implement "passthrough iff the call is in
  ## allow ∩ restrict" — the ceiling shrinks the effective `allow` set
  ## down to entries that fall under it. With `restrict` empty, the
  ## ceiling is open and the rule reduces to "iff some allow matches."
  ## With `allow` empty, no call passes regardless of `restrict`.
  ##
  ## Defensive nil-guard: this proc is exported and may be called by
  ## plugin-author intercept combinators that race against sandbox
  ## teardown, by unit tests that pass a synthetic `Verifier`, or
  ## from outside-sandbox paths where no verifier is active. Without
  ## this guard, dereferencing `v.firewallMode` later in the body
  ## SIGSEGVs. With no verifier the answer is "raise" (no firewall
  ## is configured to permit the call).
  if v.isNil:
    return fdRaise
  let pluginPasses = plugin.supportsPassthrough() and
                     plugin.passthroughFor(procName)
  if pluginPasses:
    return fdAllow
  # Hot-path optimization: tokenize the fingerprint ONCE per call and
  # share the tokens across both ceiling (`restrict`) and floor
  # (`allow`) loops. The pre-refactor shape called the public
  # `sandboxRestrictsFor` and `sandboxAllowsFor` procs, each of which
  # internally re-tokenized the same string — wasteful in sandboxes
  # carrying many rules where this proc runs on every intercepted
  # interaction.
  let tokens = tokenizeMatcherHead(fingerprint)
  let r = sandboxRestrictsForTokens(v, plugin, procName, fingerprint,
                                    tokens)
  if r.active and not r.allows:
    return (if v.firewallMode == fmWarn: fdWarn else: fdRaise)
  if sandboxAllowsForTokens(v, plugin, procName, fingerprint, tokens):
    return fdAllow
  if v.firewallMode == fmWarn: fdWarn else: fdRaise

proc firewallDecide*(v: Verifier, plugin: Plugin, procName,
                     fingerprint: string): FirewallDecision {.raises: [].} =
  ## Side-effecting decision used by the intercept combinators. In the
  ## `fdWarn` lane, this proc emits the stderr warning so the TRM body
  ## structure remains a single `if fdRaise: raise; spyBody` — the
  ## flattest shape that doesn't trip Nim 2.2.8's TRM rewriter on
  ## multi-branch templates (see `tripwire/intercept` for the full
  ## reproducer).
  result = firewallDecideRaw(v, plugin, procName, fingerprint)
  if result == fdWarn:
    emitFirewallWarning(plugin.name, procName, fingerprint)

proc firewallShouldRaise*(v: Verifier, plugin: Plugin, procName,
                          fingerprint: string): bool {.inline, raises: [].} =
  ## Bool-returning convenience used inside TRM combinator bodies.
  ## Emits the warn-side stderr line as a side effect of running
  ## `firewallDecide`. Returns `true` iff the call should raise
  ## `UnmockedInteractionDefect`. Lifted out of the combinator body so
  ## the TRM body parses as a single `if`-statement, dodging a Nim
  ## 2.2.8 dirty-template rewriter SIGSEGV on multi-branch bodies.
  firewallDecide(v, plugin, procName, fingerprint) == fdRaise

# ---- Sandbox templates ---------------------------------------------------

template sandbox*(body: untyped) =
  ## Lexical scope: push fresh verifier, run body, pop, verifyAll.
  ## `verifyAll` lives in `tripwire/verify` which imports this module;
  ## to avoid a circular `bind`, it resolves at instantiation site
  ## (caller must `import tripwire/verify` alongside `tripwire/sandbox`).
  ##
  ## **First-violation-wins semantics.** If the body raises (e.g., a TRM
  ## fired `UnmockedInteractionDefect`), that defect IS the verification
  ## failure — we pop the verifier but do NOT re-run `verifyAll`, because
  ## a second raise inside a `finally` would mask the original with a
  ## spurious `UnassertedInteractionsDefect` (the timeline entry for the
  ## unmocked call is unasserted by definition, since the body never
  ## reached the `assert` clause). Only run `verifyAll` on normal
  ## completion, where it reports the first unmet guarantee.
  bind popVerifier, pushVerifier, newVerifier, getCurrentException
  let nfV = pushVerifier(newVerifier())
  try:
    body
  finally:
    discard popVerifier()
    # First-violation-wins: if an exception (including Defect) is already
    # in flight from body, don't re-run verifyAll — doing so would raise
    # UnassertedInteractionsDefect inside a `finally`, masking the
    # original (and more informative) failure.
    if getCurrentException() == nil:
      nfV.verifyAll()

template sandbox*(name: static string, body: untyped) =
  ## Named variant: labels the fresh verifier so error messages carry
  ## the user-provided name. Semantics otherwise identical to
  ## `sandbox*(body)`; see its docstring for first-violation-wins details.
  bind popVerifier, pushVerifier, newVerifier, getCurrentException
  let nfV = pushVerifier(newVerifier(name))
  try:
    body
  finally:
    discard popVerifier()
    if getCurrentException() == nil:
      nfV.verifyAll()
