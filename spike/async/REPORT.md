# Async / multisync TRM interception — spike report

Env: Nim 2.2.6 on macOS arm64. Compiler invocation for all tests:
`nim c -r --hint:all:off <file>.nim`. Wall time per test: <3s. No timeouts hit.

## Q1 — User-defined async proc: **VIABLE**

File: `q1_user_async.nim`. A `{.async.}` proc `fetchAsync(url): Future[string]`
and a TRM `template rewriteFetch*{fetchAsync(url)}(url: string): Future[string]`
that constructs a pre-completed future with `"mocked result"`.

Result: `result=mocked result` and `rewriteCount=1`. No compile warnings. The
real proc body never executes (confirmed by `q1_call_site_check.nim` which
echoes a `REAL BODY:` marker in the real `fetchAsync` and `TRM body running;`
in the rewrite). Output ordering was:

    -- before call --
    TRM body running; url=http://x
    -- after call, before waitFor --
    -- after waitFor --

**This resolves the critical question:** the TRM fires synchronously at the
call site, BEFORE the async dispatcher ever sees anything. It runs in the
pattern-matching phase, before `{.async.}`'s state-machine transform runs on
the surrounding context. The interception is structurally equivalent to the
sync TRM case — the "async-ness" is entirely in the `Future[T]` the rewrite
returns, not in how/when the rewrite itself executes.

## Q2 — multisync-generated AsyncHttpClient.get: **VIABLE**

File: `q2_multisync_exception.nim`. TRM:
`template rewriteAsyncGet*{get(c, url)}(c: AsyncHttpClient, url: string): Future[AsyncResponse]`.
Because constructing a valid `AsyncResponse` requires private fields, the TRM
body returns a failed future carrying a distinctive `MarkerError`. If the TRM
fires, `waitFor c.get("http://example.invalid/")` should raise `MarkerError`
instead of making a network call.

Result: `caught MarkerError: TRM fired on AsyncHttpClient.get` / `asyncRewrites=1` /
`sawMarker=true`. The invalid host was never contacted. The TRM matches the
async variant produced by `multisync` just as the earlier sync-variant spike
matched `HttpClient.get`. Pattern signature parity: both use the method-style
`get(client, url)` shape; the client-type parameter on the TRM is what steers
matching to sync vs async.

One footnote: returning a failed Future with a sentinel error is a clean way
to prove TRM firing without fabricating a concrete AsyncResponse. This is a
useful nimfoot idiom for "we want to verify the mock fired but we don't care
about the return value" tests.

## Q3 — `await` itself: **NOT VIABLE (expected)**

File: `q3_await.nim`. TRM: `template rewriteAwait*{await(f)}(f: Future[string]): string`.
Consumer proc uses `let v = await f` inside `{.async.}`.

Result: `result=real future value` / `awaitRewrites=0`. The TRM never matches.
This is consistent with `await` being a magic/macro expanded by the async
transform BEFORE pattern-matching sees the expression. `await` is not a regular
proc call and isn't TRM-addressable. **This is fine** — mocking at the call
site (Q1/Q2) is the right layer anyway. Intercepting await would be the wrong
abstraction for a mocking library.

## Q4 — chronos: **VIABLE, with a template-composition gotcha**

File: `q4_chronos.nim` plus `q4_chronos_sanity.nim`. Chronos 4.2.2 is installed
in the active mise nim. Same shape as Q1.

Sanity check (bare `newFuture[T]("x")` + `complete(f, "hello")` + `waitFor f`)
works. Inside a TRM body, the first attempt failed at compile time:

    q4_chronos.nim(16, 11) Error: wrong number of arguments

Chronos' `complete` is itself a template that calls `getSrcLocation()`; when
nested inside a pattern-template body the macro expansion produces the wrong
arg count. Workaround: move the completion into a plain helper proc and call
the helper from the TRM body. With that:

    proc makeMocked(val: string): Future[string] =
      result = newFuture[string]("fakeFetch")
      result.complete(val)

    template rewriteFetch*{fetchAsync(url)}(url: string): Future[string] =
      inc(rewriteCount)
      makeMocked("mocked result")

Result: `result=mocked result` / `rewriteCount=1`.

Design implication for nimfoot: generated TRM bodies targeting chronos should
delegate Future construction to a plain proc in the nimfoot runtime rather
than inline chronos's heavily-templated `complete`/`fail`. This is probably
good hygiene for `asyncdispatch` as well — the inline form happens to work
there, but a helper proc keeps TRM bodies compact and avoids ambient-macro
surprises.

## Recommendation for v0

Async interception is **in-scope for v0**. Supported shape:

1. **User async procs**: `{.async.}` procs are fully mockable via TRMs shaped
   like `template {proc(args)}(args: ATs): Future[R]`. The rewrite fires
   synchronously at the call site; the real body never runs.
2. **Stdlib async procs via multisync** (e.g. `AsyncHttpClient.get`): same,
   matched by specifying the async client type as the first TRM parameter.
3. **Helper-proc Future construction**: generate TRM bodies that call nimfoot
   runtime helpers (`nimfoot.completeFuture`, `nimfoot.failFuture`) rather
   than inlining runtime-specific Future APIs. Makes chronos compatible.
4. **Chronos**: treat as a secondary target. Same codegen works as long as
   bodies delegate to helper procs. No extra pragmas needed at the mock def.

Deferred to post-v0:

- **`await` interception**: impossible via TRMs (confirmed). If users want to
  observe await points, nimfoot would need a separate macro-based approach.
  Not planned.
- **Returning fabricated async response types with private fields**: users
  will need an escape hatch (a "the mock fired but threw" shape) or nimfoot
  will need adapters for common stdlib return types. The failed-Future idiom
  from Q2 covers the "I just want to assert this got called" case.
