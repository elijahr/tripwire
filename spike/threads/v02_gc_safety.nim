## v0.2 GC-safety probe — empirical check of refc's thread-local heap behavior
## for a shared `ref object` mutated from a child thread.
##
## Design citations: §8.1 (decision), §8.2 (evidence), §8.3 (this probe).
##
## Build:
##   nim c --gc:orc  --threads:on -r --hint:all:off v02_gc_safety.nim
##   nim c --gc:refc --threads:on -r --hint:all:off v02_gc_safety.nim
##
## Expected: under orc the post-join count is 1 (child's mutation visible);
## under refc the mutation is silently dropped or the build refuses.

type SharedCounter = ref object
  count: int

proc childBump(sc: SharedCounter) {.thread, nimcall.} =
  sc.count.inc

proc main() =
  let gcKind =
    when defined(gcRefc): "refc"
    elif defined(gcOrc):  "orc"
    elif defined(gcArc):  "arc"
    else:                 "other"
  echo "gc kind: ", gcKind
  let sc = SharedCounter(count: 0)
  var t: Thread[SharedCounter]
  createThread(t, childBump, sc)
  joinThread(t)
  echo "post-join count: ", sc.count

main()
