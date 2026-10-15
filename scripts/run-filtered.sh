#!/usr/bin/env bash
# lean-tokens: run a noisy command, keep the full log, print only what matters.
#
#   bash run-filtered.sh '<command>'
#
# Short output is printed as is. Long output is cut down to lines that look like
# failures or errors (with a little context) plus the last lines, which is where
# test runners and compilers print their summary. The exit code is preserved.
#
# LEAN_TOKENS_MAX_LINES   print everything up to this many lines (default 60)
# LEAN_TOKENS_TAIL_LINES  summary lines kept from the end (default 30)

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: run-filtered.sh '<command>'" >&2
  exit 2
fi

max_full="${LEAN_TOKENS_MAX_LINES:-60}"
tail_lines="${LEAN_TOKENS_TAIL_LINES:-30}"

dir="${TMPDIR:-/tmp}"
dir="${dir%/}/lean-tokens"
mkdir -p "$dir" 2>/dev/null || dir="/tmp"
# Remove logs older than a day.
find "$dir" -maxdepth 1 -name 'run-*' -type f -mtime +1 -exec rm -f {} + 2>/dev/null
log="$(mktemp "$dir/run-XXXXXXXX" 2>/dev/null)" || log="$dir/run-$$"

bash -c "$cmd" >"$log" 2>&1
status=$?

esc="$(printf '\033')"
strip_ansi() { sed "s/${esc}\[[0-9;]*[A-Za-z]//g"; }

total="$(wc -l <"$log" | tr -d '[:space:]')"
if [ "${total:-0}" -le "$max_full" ]; then
  strip_ansi <"$log"
else
  echo "[lean-tokens] $total lines of output, trimmed to failures and the summary. Full log: $log"
  pattern='(fail|failed|failing|failure|error|exception|traceback|panic|assert|✗|✕|✘|×)'
  matches="$(strip_ansi <"$log" | grep -n -i -E -A 6 "$pattern" | head -n 120)"
  if [ -n "$matches" ]; then
    echo "--- matching lines (numbers are line numbers in the full log) ---"
    printf '%s\n' "$matches"
  fi
  echo "--- last $tail_lines lines (per-test ✓ lines hidden) ---"
  strip_ansi <"$log" | grep -v -E '^[[:space:]]*(✓|✔|√)[[:space:]]' | tail -n "$tail_lines"
fi
echo "[lean-tokens] exit code: $status"
exit "$status"
