## tests/test_docs_presence.nim — docs surface acceptance.
##
## Verifies that user-facing documentation exists and carries the
## contractually-required surface markers (alpha callout, FFI mention,
## plugin authoring rules, spike #2 report). Shelling out to
## fileExists rather than parsing markdown because the goal is to catch
## accidental deletion, not grammatical correctness.
import std/[unittest, os, strutils]

# The tests shell out to the filesystem relative to the repo root; they
# must run with the repo root as the CWD (which nimble test ensures).
const RepoRoot = currentSourcePath().parentDir().parentDir()

suite "docs presence (H4/H5/H6)":
  test "quickstart exists":
    check fileExists(RepoRoot / "docs" / "quickstart.md")

  test "README exists with alpha callout and plugin coverage":
    # Commit 1f40606 rewrote the README and replaced the standalone
    # "SCOPE" callout with a "## What tripwire is, and isn't" section
    # plus a "## v0.0.x is alpha" callout. The behavioral guarantee of
    # this test is unchanged: the README must clearly mark scope/alpha
    # caveats and enumerate plugin coverage so accidental deletion of
    # those load-bearing sections fails CI.
    let path = RepoRoot / "README.md"
    check fileExists(path)
    let r = readFile(path)
    check "## What tripwire is, and isn't" in r
    check "## v0.0.x is alpha" in r
    check "## Plugin coverage" in r
    check "FFI" in r

  test "plugin-authoring doc enumerates rules":
    let path = RepoRoot / "docs" / "plugin-authoring.md"
    check fileExists(path)
    let p = readFile(path)
    # Rule count sanity: each rule is tagged as `Rule N` somewhere
    # in the body; pin the lower bound at Rule 13 (current count is 14
    # post-firewall-only addition, but the test stays count-flexible
    # so adding a new rule does not require a test edit).
    check "Rule 1" in p
    check "Rule 13" in p
    # Canonical TRM body helper must be mentioned somewhere — users
    # grep for this when starting a plugin.
    check "tripwireInterceptBody" in p

  test "spike #2 cap report exists":
    check fileExists(RepoRoot / "spike" / "cap" / "REPORT.md")

  test "v0.3 roadmap exists and enumerates deferred items":
    # The roadmap pins what v0 deliberately does not ship and where it
    # would land in v0.3. We pin canonical deferred-item labels (by the
    # exact text used in the doc) so accidental truncation or loss of
    # known v0.3 surfaces fails the test.
    let path = RepoRoot / "docs" / "roadmap-v0.3.md"
    check fileExists(path)
    let r = readFile(path)
    check "refc + threads" in r
    check "Concurrent multi-spawn" in r
    check "typestate" in r.toLowerAscii
    check "chronos" in r.toLowerAscii
    check "FFI" in r
