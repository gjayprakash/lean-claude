#!/usr/bin/env bash
# lean-tokens: PreToolUse hook for the Bash tool.
#
# Off by default. When "Trim test, build and lint output" is on (/config), a
# plain test/build/lint/typecheck command such as `npm test` or `pytest -q` is
# rewritten to run through run-filtered.sh, so Claude reads only failures and a
# summary instead of thousands of lines. The full log stays in a temp file.
#
# Only simple commands are touched: one runner from the allowlist below, an
# optional `cd <dir> &&` prefix, optional VAR=value prefixes, and arguments made
# of ordinary characters. Anything with pipes, redirects, `;`, `$`, backticks,
# subshells or newlines is left alone. Any problem here means "do nothing".

set -u

opt="$(printf '%s' "${CLAUDE_PLUGIN_OPTION_FILTER_NOISY_OUTPUT:-false}" | tr '[:upper:]' '[:lower:]')"
case "$opt" in
  true|1|yes|on) ;;
  *) exit 0 ;;
esac

input="$(cat)"
[ -n "$input" ] || exit 0

# ---- JSON helpers: jq, then python3, then node. With none of them, do nothing.
json_tool=""
if command -v jq >/dev/null 2>&1; then json_tool=jq
elif command -v python3 >/dev/null 2>&1; then json_tool=python3
elif command -v node >/dev/null 2>&1; then json_tool=node
else exit 0
fi

# Prints "<bg 0|1><TAB><command>", or nothing when the command has a newline.
read_input() {
  case "$json_tool" in
    jq)
      printf '%s' "$input" | jq -r '
        (.tool_input.command // "") as $c
        | if ($c | test("\n")) then empty
          else ((if .tool_input.run_in_background then "1" else "0" end) + "\t" + $c) end' 2>/dev/null ;;
    python3)
      python3 -c '
import json, sys
try:
    t = json.loads(sys.argv[1]).get("tool_input") or {}
except Exception:
    sys.exit(0)
c = str(t.get("command") or "")
if "\n" not in c:
    sys.stdout.write(("1" if t.get("run_in_background") else "0") + "\t" + c)
' "$input" 2>/dev/null ;;
    node)
      node -e '
let t = {};
try { t = JSON.parse(process.argv[1]).tool_input || {}; } catch (e) { process.exit(0); }
const c = String(t.command || "");
if (!c.includes("\n")) process.stdout.write((t.run_in_background ? "1" : "0") + "\t" + c);
' "$input" 2>/dev/null ;;
  esac
}

# Prints the hook's JSON answer with tool_input.command replaced by $1.
write_output() {
  local new_cmd="$1"
  local reason="lean-tokens: trimmed output for a plain test/build/lint command (full log kept in a temp file)"
  case "$json_tool" in
    jq)
      printf '%s' "$input" | jq -c --arg c "$new_cmd" --arg r "$reason" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "allow",
          permissionDecisionReason: $r,
          updatedInput: ((.tool_input // {}) + {command: $c})
        }}' ;;
    python3)
      python3 -c '
import json, sys
t = dict(json.loads(sys.argv[1]).get("tool_input") or {})
t["command"] = sys.argv[2]
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": sys.argv[3],
    "updatedInput": t}}))
' "$input" "$new_cmd" "$reason" ;;
    node)
      node -e '
const t = Object.assign({}, JSON.parse(process.argv[1]).tool_input || {});
t.command = process.argv[2];
console.log(JSON.stringify({hookSpecificOutput: {
  hookEventName: "PreToolUse",
  permissionDecision: "allow",
  permissionDecisionReason: process.argv[3],
  updatedInput: t}}));
' "$input" "$new_cmd" "$reason" ;;
  esac
}

line="$(read_input)" || exit 0
[ -n "$line" ] || exit 0
tab="$(printf '\t')"
bg="${line%%"$tab"*}"
cmd="${line#*"$tab"}"
[ "$bg" = "0" ] || exit 0

# Trim surrounding whitespace.
cmd="${cmd#"${cmd%%[![:space:]]*}"}"
cmd="${cmd%"${cmd##*[![:space:]]}"}"
[ -n "$cmd" ] || exit 0

# Optional `cd <dir> && ` prefix, kept outside the wrapper so the shell's
# working directory changes exactly as it would have.
cd_dir=""
re_cd='^cd[[:space:]]+([^[:space:]]+)[[:space:]]*&&[[:space:]]*(.+)$'
if [[ "$cmd" =~ $re_cd ]]; then
  cd_dir="${BASH_REMATCH[1]}"
  cmd="${BASH_REMATCH[2]}"
fi

# Only ordinary characters: no ; & | < > $ ` ( ) { } \ or control characters.
re_safe="^[][A-Za-z0-9 _./:=@%+,*?~'\"-]+\$"
[[ "$cmd" =~ $re_safe ]] || exit 0
if [ -n "$cd_dir" ]; then
  re_safe_dir="^[A-Za-z0-9_./~@%+,:-]+\$"
  [[ "$cd_dir" =~ $re_safe_dir ]] || exit 0
fi

# Never wrap watch modes or dev servers.
case " $cmd " in
  *" --watch"*|*" -w "*|*" watch "*|*" --ui"*|*" dev "*|*" serve "*|*" start "*) exit 0 ;;
esac

# Strip leading VAR=value assignments before matching the runner.
runner="$cmd"
re_env='^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.+)$'
while [[ "$runner" =~ $re_env ]]; do runner="${BASH_REMATCH[1]}"; done

scripts='(test|t|build|lint|typecheck|type-check|tsc|check|test:[A-Za-z0-9:_-]+|build:[A-Za-z0-9:_-]+|lint:[A-Za-z0-9:_-]+)'
runners=(
  "(npm|pnpm|yarn|bun)( run| run-script)? $scripts"
  "(npx|pnpm exec|pnpm dlx|yarn dlx|yarn exec|bunx)( --yes| -y)? (jest|vitest( run)?|mocha|ava|tsc|eslint|biome (check|lint|ci)|playwright test|cypress run|nx (test|build|lint|run-many)|turbo( run)? (test|build|lint))"
  "(jest|vitest( run)?|mocha|ava|tsc|eslint|biome (check|lint|ci))"
  "(python3? -m )?(pytest|unittest|mypy|pyright|flake8|pylint|tox|nox)"
  "(ruff check|uv run (pytest|mypy|ruff check)|poetry run (pytest|mypy))"
  "go (test|build|vet)"
  "cargo (test|build|check|clippy|nextest run)"
  "(\./)?(mvnw|mvn|gradlew|gradle)( [^ ]+)* (test|build|check|verify|compile|package)"
  "(bundle exec )?(rspec|rake test|rails test)"
  "(php artisan test|(\./)?vendor/bin/(phpunit|pest)|phpunit)"
  "dotnet (test|build)"
  "(mix test|swift (test|build)|deno (test|lint|check)|ctest|flutter test|dart test)"
  "make( -[A-Za-z0-9]+)* (test|check|build|lint)"
)

matched=0
for r in "${runners[@]}"; do
  re="^${r}([[:space:]].*)?\$"
  if [[ "$runner" =~ $re ]]; then matched=1; break; fi
done
[ "$matched" = "1" ] || exit 0

script_dir="${CLAUDE_PLUGIN_ROOT:-}"
if [ -n "$script_dir" ]; then
  script_dir="$script_dir/scripts"
else
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
wrapper="$script_dir/run-filtered.sh"
[ -f "$wrapper" ] || exit 0

# Single-quote a string for the shell.
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

new_cmd="bash $(sq "$wrapper") $(sq "$cmd")"
if [ -n "$cd_dir" ]; then
  new_cmd="cd $cd_dir && $new_cmd"
fi

write_output "$new_cmd"
exit 0
