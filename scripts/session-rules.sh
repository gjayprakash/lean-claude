#!/usr/bin/env bash
# lean-tokens: SessionStart hook.
# Prints a short checklist that Claude Code adds to the session's context.
# Turn it off with /config -> lean-tokens -> "Lean rules at session start".

case "$(printf '%s' "${CLAUDE_PLUGIN_OPTION_SESSION_RULES:-true}" | tr '[:upper:]' '[:lower:]')" in
  false|0|no|off) exit 0 ;;
esac

case "$(printf '%s' "${CLAUDE_PLUGIN_OPTION_FILTER_NOISY_OUTPUT:-false}" | tr '[:upper:]' '[:lower:]')" in
  true|1|yes|on)
    output_rule="- Run test, build, lint and typecheck commands plainly, with no pipes or redirects: lean-tokens trims their output to failures and a summary and prints where the full log is. For other commands, use quiet flags and pipe long output through tail/head/grep. Never print lockfiles, build artifacts, minified or generated files." ;;
  *)
    output_rule="- Keep command output small: use quiet or summary flags, pipe long output through tail/head/grep, and never print lockfiles, build artifacts, minified or generated files." ;;
esac

cat <<EOF
[lean-tokens] Work token-efficiently in this session:
- Locate before you read: Grep/Glob first, then Read only the lines you need (offset/limit) from large files. Don't re-read a file you just wrote or edited.
- Change files with targeted edits. Never rewrite a whole file to change a few lines.
$output_rule
- Hand broad exploration, log digging and long test runs to a subagent (Explore for searches) and keep only its summary.
- Keep replies short. Don't restate the plan or echo unchanged code; show only the changed lines.
- On a large, ambiguous task, ask one clarifying question instead of exploring on a guess.
- When the user moves to an unrelated task, suggest /clear (or /lean-tokens:handoff first if they will come back to this work).
EOF
exit 0
