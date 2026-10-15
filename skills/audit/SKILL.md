---
name: audit
description: Audit this Claude Code setup for token waste (CLAUDE.md size, MCP servers, skills, model and thinking settings, repo hotspots) and give a short, ranked list of fixes.
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/audit.sh)
---

# Token audit

1. Run this once. It is read-only and collects everything in a single call, so don't open the config files yourself:

   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/audit.sh
   ```

2. From its output, find what is costing tokens. Use these rules of thumb:

   | Check | Flag when | Fix |
   | --- | --- | --- |
   | Always-loaded instructions (CLAUDE.md files, their @imports, unscoped `.claude/rules`) | over ~200 lines or ~3k tokens in total | Keep only what every task needs. Move workflow-specific sections (deploys, migrations, PR review) into skills, and file-type rules into `.claude/rules/*.md` with `paths:` frontmatter so they load only when relevant |
   | MCP servers | any server the user doesn't use in this project | Disable it per project in `/mcp`. Prefer CLIs (`gh`, `aws`, `gcloud`, `psql`) which add nothing to context |
   | Skills, agents, plugins | more than ~30 skills, or plugins the user doesn't use | Each description sits in context every session. Disable unused plugins in `/plugin` and delete stale personal skills |
   | Default model | the most capable model set as the default for everyday work | Default to a lighter model and switch up with `/model` for hard problems. Simple subagents can use `model: haiku` |
   | Thinking | high effort or a large `MAX_THINKING_TOKENS` applied to everything | Lower `/effort` for routine work. Thinking is billed as output |
   | Status line | no `statusLine` | `/statusline` to show context usage, so the user knows when to `/clear` |
   | Repo hotspots | large tracked files, or build output that isn't gitignored | gitignore generated folders. For files Claude should never open, add `Read(...)` deny rules in `.claude/settings.json`, e.g. `"deny": ["Read(./dist/**)"]` |

3. Reply in this shape and keep it under ~25 lines:
   - One line with the total always-loaded instruction size.
   - **Top fixes**: at most 5, ranked by tokens saved per session. For each: what you found (with the number), why it costs tokens, and the exact fix (command, setting or file change).
   - **Habits**: at most 3 one-liners chosen to match what you found (for example `/clear` between tasks, `/compact <focus>`, plan mode for big changes).
   - Skip checks that look fine. Don't list them.

4. Offer to apply the safe fixes (trim or split CLAUDE.md, add `.gitignore` entries or deny rules, write a skill from a CLAUDE.md section). Make changes only after the user says yes. Never delete instructions without moving them somewhere. Show the new CLAUDE.md line count when done.
