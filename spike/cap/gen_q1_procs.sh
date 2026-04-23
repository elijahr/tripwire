#!/usr/bin/env bash
# Emits N call sites, each in its OWN proc, then calls all of them.
# This tests whether the cap is per-module-body vs per-proc-body.
set -euo pipefail
N="$1"
OUT="$2"
{
  printf '## Generated test: %s call sites, one per proc.\n' "$N"
  printf 'import nimfoot_q1, common_q1\n\n'
  for ((i=0; i<N; i++)); do
    printf 'proc call_%d(): int = target(%d, %d)\n' "$i" "$i" "$((i+1))"
  done
  printf '\nvar sink = 0\n'
  for ((i=0; i<N; i++)); do
    printf 'sink = sink + call_%d()\n' "$i"
  done
  printf '\necho "sink=", sink\n'
  printf 'echo "rewriteCount=", rewriteCount\n'
  printf 'echo "expected=%s"\n' "$N"
} > "$OUT"
