#!/usr/bin/env bash
# lean-tokens: collect the facts /lean-tokens:audit needs in one cheap pass,
# so Claude doesn't spend tokens opening config files one by one.
# Read-only. Prints a compact report and always exits 0.

set -u

home="${HOME:-~}"
cwd="$(pwd)"
root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$root" ] || root="$cwd"

json_tool=""
if command -v jq >/dev/null 2>&1; then json_tool=jq
elif command -v python3 >/dev/null 2>&1; then json_tool=python3
fi

lines_of() { wc -l <"$1" 2>/dev/null | tr -d '[:space:]'; }
bytes_of() { wc -c <"$1" 2>/dev/null | tr -d '[:space:]'; }
tok() { # rough token estimate from bytes (~4 bytes per token)
  local b="${1:-0}"
  if [ "$b" -ge 4000 ]; then
    awk -v b="$b" 'BEGIN { printf "~%.1fk tok", b / 4000 }'
  else
    echo "~$((b / 4)) tok"
  fi
}
short() { # paths relative to the project, then to home, to keep the report small
  case "$1" in
    "$root"/*) echo "./${1#"$root"/}" ;;
    "$home"/*) echo "~${1#"$home"}" ;;
    *) echo "$1" ;;
  esac
}

echo "== lean-tokens audit =="
echo "project: $(case "$root" in "$home"/*) echo "~${root#"$home"}" ;; *) echo "$root" ;; esac)$( [ -d "$root/.git" ] && echo '  (git repo)')"
if command -v claude >/dev/null 2>&1; then
  echo "claude code: $(claude --version 2>/dev/null | head -n 1)"
fi
echo "json parser: ${json_tool:-none (install jq for a fuller report)}"

# ---------------------------------------------------------------------------
echo
echo "[instructions loaded at session start]"
always_bytes=0
always_lines=0
for f in "$home/.claude/CLAUDE.md" "$root/CLAUDE.md" "$root/.claude/CLAUDE.md" "$root/CLAUDE.local.md"; do
  [ -f "$f" ] || continue
  l="$(lines_of "$f")"; b="$(bytes_of "$f")"
  imports="$(grep -c -E '(^|[[:space:]])@[~./A-Za-z0-9_-]+' "$f" 2>/dev/null || true)"
  always_bytes=$((always_bytes + b)); always_lines=$((always_lines + l))
  printf '  %-44s %5s lines  %s' "$(short "$f")" "$l" "$(tok "$b")"
  [ "${imports:-0}" -gt 0 ] && printf '  (%s @import line(s): imported files load too)' "$imports"
  printf '\n'
done
for d in "$home/.claude/rules" "$root/.claude/rules"; do
  [ -d "$d" ] || continue
  n=0; scoped=0; ub=0; ul=0
  while IFS= read -r f; do
    n=$((n + 1))
    if head -n 15 "$f" | grep -q -E '^paths:'; then
      scoped=$((scoped + 1))
    else
      ub=$((ub + $(bytes_of "$f"))); ul=$((ul + $(lines_of "$f")))
    fi
  done < <(find "$d" -type f -name '*.md' 2>/dev/null)
  always_bytes=$((always_bytes + ub)); always_lines=$((always_lines + ul))
  echo "  $(short "$d")/: $n rule file(s), $scoped path-scoped; unscoped rules: $ul lines $(tok "$ub")"
done
[ -f "$root/AGENTS.md" ] && echo "  $(short "$root/AGENTS.md") exists ($(lines_of "$root/AGENTS.md") lines; loaded only if CLAUDE.md imports it or the project-instructions setting reads it)"
echo "  TOTAL always-loaded: $always_lines lines $(tok "$always_bytes")"
nested="$(find "$root" -mindepth 2 -maxdepth 5 -name CLAUDE.md \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/build/*' 2>/dev/null | head -n 10)"
if [ -n "$nested" ]; then
  echo "  nested CLAUDE.md (load when Claude works in that folder):"
  while IFS= read -r f; do
    printf '    %-42s %5s lines  %s\n' "${f#"$root"/}" "$(lines_of "$f")" "$(tok "$(bytes_of "$f")")"
  done <<<"$nested"
fi

# ---------------------------------------------------------------------------
echo
echo "[settings]"
settings_files=("$home/.claude/settings.json" "$root/.claude/settings.json" "$root/.claude/settings.local.json")
any_settings=0
for f in "${settings_files[@]}"; do
  [ -f "$f" ] || continue
  any_settings=1
  echo "  $(short "$f"):"
  case "$json_tool" in
    jq)
      jq -r '
        def show(k; v): "    \(k): \(v)";
        (to_entries[] | select(.key | test("model|effort|think|statusLine|outputStyle|compact|cleanupPeriod"; "i"))
          | show(.key; (.value | if type == "object" then (keys | join(",")) + " (set)" else tostring end))),
        ((.env // {}) | to_entries[] | select(.key | test("MODEL|THINK|EFFORT|OUTPUT_TOKENS|COMPACT|MCP|DISABLE"; "i"))
          | show("env." + .key; .value)),
        (if .hooks then show("hooks"; (.hooks | keys | join(", "))) else empty end),
        (if .enabledPlugins then show("enabledPlugins"; ([.enabledPlugins | to_entries[] | select(.value == true) | .key] | join(", "))) else empty end),
        (if .permissions.deny then show("permissions.deny"; (.permissions.deny | length | tostring) + " rule(s)") else empty end)
      ' "$f" 2>/dev/null || echo "    (could not parse)" ;;
    python3)
      python3 - "$f" <<'PY' 2>/dev/null || echo "    (could not parse)"
import json, re, sys
d = json.load(open(sys.argv[1]))
for k, v in d.items():
    if re.search(r"model|effort|think|statusLine|outputStyle|compact|cleanupPeriod", k, re.I):
        print(f"    {k}: {','.join(v) + ' (set)' if isinstance(v, dict) else v}")
for k, v in (d.get("env") or {}).items():
    if re.search(r"MODEL|THINK|EFFORT|OUTPUT_TOKENS|COMPACT|MCP|DISABLE", k, re.I):
        print(f"    env.{k}: {v}")
if d.get("hooks"):
    print("    hooks: " + ", ".join(d["hooks"].keys()))
if d.get("enabledPlugins"):
    print("    enabledPlugins: " + ", ".join(k for k, v in d["enabledPlugins"].items() if v is True))
deny = (d.get("permissions") or {}).get("deny")
if deny:
    print(f"    permissions.deny: {len(deny)} rule(s)")
PY
      ;;
    *) grep -n -E '"(model|effortLevel|alwaysThinkingEnabled|statusLine|MAX_THINKING_TOKENS)"' "$f" | sed 's/^/    /' ;;
  esac
done
[ "$any_settings" = 1 ] || echo "  (no settings files found)"

# ---------------------------------------------------------------------------
echo
echo "[mcp servers]"
if [ -f "$root/.mcp.json" ]; then
  case "$json_tool" in
    jq) echo "  project (.mcp.json): $(jq -r '(.mcpServers // {}) | keys | join(", ")' "$root/.mcp.json" 2>/dev/null)" ;;
    python3) echo "  project (.mcp.json): $(python3 -c 'import json,sys; print(", ".join((json.load(open(sys.argv[1])).get("mcpServers") or {}).keys()))' "$root/.mcp.json" 2>/dev/null)" ;;
    *) echo "  project (.mcp.json) exists" ;;
  esac
fi
if [ -f "$home/.claude.json" ]; then
  case "$json_tool" in
    jq)
      jq -r --arg p "$root" --arg c "$cwd" '
        "  user scope (~/.claude.json): " + ((.mcpServers // {}) | keys | join(", ")),
        "  local scope (this project):  " + (((.projects[$p].mcpServers // .projects[$c].mcpServers) // {}) | keys | join(", "))
      ' "$home/.claude.json" 2>/dev/null ;;
    python3)
      python3 - "$home/.claude.json" "$root" "$cwd" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
print("  user scope (~/.claude.json): " + ", ".join((d.get("mcpServers") or {}).keys()))
projects = d.get("projects") or {}
p = projects.get(sys.argv[2]) or projects.get(sys.argv[3]) or {}
print("  local scope (this project):  " + ", ".join((p.get("mcpServers") or {}).keys()))
PY
      ;;
  esac
fi
echo "  (claude.ai connectors and plugin-provided servers are not listed here; run /mcp to see everything that is connected)"

# ---------------------------------------------------------------------------
echo
echo "[skills, agents, commands]  (every skill/agent description sits in context each session)"
count_skills() {
  local d="$1" n=0 chars=0 f desc
  [ -d "$d" ] || return 0
  while IFS= read -r f; do
    n=$((n + 1))
    desc="$(awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} /^(description|when_to_use):/ {sub(/^[a-z_]+:[[:space:]]*/, ""); printf "%s", $0}' "$f" 2>/dev/null)"
    chars=$((chars + ${#desc}))
  done < <(find "$d" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null)
  [ "$n" -gt 0 ] && echo "  $(short "$d")/: $n skill(s), ~$chars chars of descriptions $(tok "$chars")"
}
count_skills "$home/.claude/skills"
count_skills "$root/.claude/skills"
for d in "$home/.claude/agents" "$root/.claude/agents" "$home/.claude/commands" "$root/.claude/commands"; do
  [ -d "$d" ] || continue
  n="$(find "$d" -type f -name '*.md' 2>/dev/null | wc -l | tr -d '[:space:]')"
  [ "$n" -gt 0 ] && echo "  $(short "$d")/: $n file(s)"
done
echo "  (plugin skills and agents count too; see enabledPlugins above and /plugin)"

# ---------------------------------------------------------------------------
if [ -d "$root/.git" ] || git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  echo
  echo "[repo hotspots]"
  big="$(cd "$root" && git ls-files -z 2>/dev/null | xargs -0 ls -l 2>/dev/null \
    | awk '$5 > 262144 {printf "%8.0f KB  %s\n", $5/1024, $NF}' | sort -rn | head -n 8)"
  if [ -n "$big" ]; then
    echo "  tracked files over 256 KB (expensive if Claude reads them):"
    printf '%s\n' "$big" | sed 's/^/  /'
  else
    echo "  no tracked files over 256 KB"
  fi
  for gd in dist build out .next .nuxt coverage target .turbo .cache storybook-static; do
    [ -e "$root/$gd" ] || continue
    if git -C "$root" check-ignore -q "$gd" 2>/dev/null; then
      echo "  $gd/ is gitignored (good: Grep/Glob skip it)"
    else
      echo "  $gd/ exists and is NOT gitignored: searches will crawl generated files"
    fi
  done
fi

# ---------------------------------------------------------------------------
echo
echo "[environment]"
envs="$(env | grep -E '^(ANTHROPIC_MODEL|ANTHROPIC_DEFAULT_[A-Z_]+_MODEL|CLAUDE_CODE_SUBAGENT_MODEL|MAX_THINKING_TOKENS|CLAUDE_CODE_MAX_OUTPUT_TOKENS|CLAUDE_CODE_EFFORT_LEVEL|CLAUDE_AUTOCOMPACT_PCT_OVERRIDE|MAX_MCP_OUTPUT_TOKENS|BASH_MAX_OUTPUT_LENGTH|ENABLE_TOOL_SEARCH)=' | sed 's/^/  /')"
if [ -n "$envs" ]; then printf '%s\n' "$envs"; else echo "  (no model/thinking/output overrides set)"; fi

exit 0
