# v0.2 GC-safety probe — report

Design citations: §8.1 (decision), §8.2 (evidence), §8.3 (this probe).
Env: Nim 2.2.6, macOS arm64. Source: `spike/threads/v02_gc_safety.nim`.

## Fixture

Main thread constructs a shared `ref object` (`SharedCounter` with an `int`
field `count`), passes it to a child via `createThread(t, childBump, sc)`,
joins, then prints `sc.count`. Child's sole action: `sc.count.inc`. Does
the parent observe the child's mutation after `joinThread`?

## orc result

```
gc kind: orc
post-join count: 1
```

Parent observes child's mutation. The shared `ref object` is reachable
across threads under orc; the increment lands on the object the parent
still holds. Matches design §8.2 expectation.

## refc result

```
gc kind: refc
post-join count: 0
```

Parent does NOT observe child's mutation. No segfault, no compile error,
no runtime warning — refc allocates `ref` graphs in thread-local heap
partitions; the child's write never becomes visible to the parent's
post-join read. This "silent drop" is §8.2's fatal failure mode for the
`tripwireThread` unified-timeline invariant and is the empirical evidence
backing §8.1's compile-time `{.error.}` for `--gc:refc --threads:on`.

## Reproducer command

```
nim c --gc:orc  --threads:on -r spike/threads/v02_gc_safety.nim
nim c --gc:refc --threads:on -r spike/threads/v02_gc_safety.nim
```
