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

## Addendum (Task 3.3): orc cycle-collector crash with the Verifier graph

The probe above only exercises a flat `SharedCounter` ref and confirms orc
preserves the across-thread-shared mutation. During Task 3.3 implementation
the broader Verifier ref graph (Verifier -> seq[Mock] -> closures, plus the
unittest dirty-template's destructor rundown of the test scope) hit a
distinct orc failure mode: a SIGSEGV inside `orc.nim:unregisterCycle` /
`rememberCycle`, called from `nimDecRefIsLastCyclicStatic` during cycle
collection of the Verifier graph after a child thread had pushed/popped
the shared `ref Verifier` on its own verifierStack. The check-level
assertions inside `tests/threads/test_tripwire_thread_basic.nim` complete
successfully; the crash fires during destructor rundown before unittest
can flush the per-test result, so the test appears to abort rather than
report `[OK]`.

Empirical evidence:
```
[Suite] withTripwireThread: happy path
Traceback (most recent call last)
.../orc.nim(553) nimDecRefIsLastCyclicStatic
.../orc.nim(509) rememberCycle
.../orc.nim(157) unregisterCycle
SIGSEGV: Illegal storage access. (Attempt to read from nil?)
```

`--mm:arc` (and `--mm:atomicArc`) avoid the cycle collector entirely and
run the same test green. Design §8.1 already lists `--gc:orc` and
`--gc:arc` as co-equal supported memory managers, so Task 3.3 selects
`--mm:arc` to unblock WI3. Matrix cell #7 (Task 3.9) selects the same GC
for the same reason. The orc path remains design-supported; investigating
whether this is a Nim 2.2.6 bug or a tripwire ref-graph shape problem is
deferred (no v0.2 metric depends on it).

Reproducer for the Task-3.3 crash:
```
nim c --gc:orc --threads:on -d:tripwireActive --import:tripwire/auto \
  -r tests/threads/test_tripwire_thread_basic.nim
```
