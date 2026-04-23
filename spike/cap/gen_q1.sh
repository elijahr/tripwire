#!/usr/bin/env bash
# Emits a Nim test program with N distinct `target(i, i+1)` call sites.
# Usage: gen_q1.sh N OUT_PATH
set -euo pipefail
N="$1"
OUT="$2"
{
  printf '## Generated test with %s call sites.\n' "$N"
  printf 'import nimfoot_q1, common_q1\n\n'
  printf 'var sink = 0\n'
  for ((i=0; i<N; i++)); do
    printf 'sink = sink + target(%d, %d)\n' "$i" "$((i+1))"
  done
  printf '\necho "sink=", sink\n'
  printf 'echo "rewriteCount=", rewriteCount\n'
  printf 'echo "expected=%s"\n' "$N"
} > "$OUT"
