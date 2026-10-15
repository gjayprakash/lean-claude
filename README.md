# lean-tokens

**Spend fewer tokens in Claude Code without getting worse results.**

Claude Code sends your whole conversation (plus CLAUDE.md, MCP server info and skill descriptions) with every request. Most wasted tokens come from three places: context that's bigger than it needs to be, noisy command output, and long sessions that never get cleared. `lean-tokens` goes after all three.

| What | How it saves tokens |
| --- | --- |
| **Lean rules at session start** (on by default) | A ~200-token checklist that steers Claude to grep before reading, read line ranges instead of whole files, make targeted edits, keep command output short, push noisy work to subagents and keep replies tight. |
| **`/lean-tokens:audit`** | One read-only script checks your setup: CLAUDE.md size, MCP servers, skills and plugins, model and thinking settings, large tracked files, build folders that aren't gitignored. Claude then gives you the top 5 fixes ranked by tokens saved, and applies them if you say yes. |
| **`/lean-tokens:handoff`** | Writes a ≤40-line handoff note for the current task, so you can `/clear` and continue later in a small context instead of carrying (or compacting) the whole conversation. |
| **`/lean-tokens:lean`** | The full lean-working playbook. Claude also picks it up when you mention tokens, usage limits or cost. |
| **Output trimming** (off by default) | Rewrites plain test/build/lint commands so Claude sees only failures plus the summary, not thousands of lines. The full log is kept in a temp file. |

## Install

In Claude Code:

```
/plugin marketplace add gjayprakash/lean-claude
/plugin install lean-tokens@lean-tokens
```

Or from your shell:

```bash
claude plugin marketplace add gjayprakash/lean-claude
claude plugin install lean-tokens@lean-tokens
```

Start a new session and the session-start rules are active.

## Use

```
/lean-tokens:audit            # find what's costing you tokens, get ranked fixes
/lean-tokens:handoff          # save state, then /clear and continue with @.claude/handoff.md
/lean-tokens:lean [task]      # switch Claude into lean mode for a task
```

## Settings

Both options appear in `/config` under lean-tokens, or can be set with `claude plugin configure lean-tokens`.

| Option | Default | What it does |
| --- | --- | --- |
| `session_rules` | `true` | Adds the lean checklist at startup, after `/clear` and after compaction. |
| `filter_noisy_output` | `false` | Trims output of plain test, build, lint and typecheck commands. |

### About output trimming

When `filter_noisy_output` is on, a PreToolUse hook rewrites commands like these:

```
npm test            pnpm run build       yarn lint          npx vitest run
pytest -q           python -m pytest     go test ./...      cargo test
tsc --noEmit        eslint src           mvn test           dotnet test
```

They then run through `scripts/run-filtered.sh`. Output of up to 60 lines is shown unchanged. Anything longer is cut to the lines that look like failures or errors (with a little context) plus the last 30 lines, with the exit code kept. The full log path is printed, so Claude can grep it instead of running the command again.

Safety rules:

- Only simple commands are touched: one known runner, optional `cd <dir> &&` and `VAR=value` prefixes, and ordinary arguments. Anything with pipes, redirects, `;`, `$`, backticks, subshells or newlines is left alone, and so are watch modes, dev servers and package installs.
- **Matching commands run without a permission prompt while this option is on.** Your deny and ask rules still apply. Leave the option off if you want to approve every test run yourself.
- It needs `jq`, `python3` or `node` to parse the hook input. If none of them is installed, it does nothing.
- `LEAN_TOKENS_MAX_LINES` and `LEAN_TOKENS_TAIL_LINES` change the thresholds.

## Habits that save the most

The plugin helps, but these habits matter more:

1. **`/clear` between unrelated tasks.** It costs nothing, and stale context is resent with every message.
2. **Use `/compact <what to keep>` for a long single task.** Compaction reads the whole conversation, so prefer `/clear` plus a handoff when you don't need continuity.
3. **Match the model to the job.** A lighter model handles most edits. Switch up with `/model` for hard problems, and lower `/effort` for routine work.
4. **Be specific.** "Add validation to `createUser` in `users.service.ts`" reads 1 file. "Improve the users module" reads 20.
5. **Use plan mode (Shift+Tab) for big changes** and press Esc early when Claude heads the wrong way. Fixing a plan is cheaper than redoing code.
6. **Keep CLAUDE.md under ~200 lines.** Move workflow-specific instructions into skills, which load only when used.
7. **Check `/context` and `/usage`** to see what's actually filling your window and your plan limits.

These are drawn from Anthropic's [Manage costs effectively](https://code.claude.com/docs/en/costs) guide.

## Layout

```
.claude-plugin/plugin.json       manifest + the two options
.claude-plugin/marketplace.json  makes this repo installable as a marketplace
skills/lean/SKILL.md             lean-working playbook
skills/audit/SKILL.md            /lean-tokens:audit
skills/handoff/SKILL.md          /lean-tokens:handoff
hooks/hooks.json                 SessionStart rules + PreToolUse output trimming
scripts/                         session-rules.sh, filter-noisy-output.sh, run-filtered.sh, audit.sh
```

Works on macOS and Linux. On Windows it needs Git Bash or WSL.

## Contributing

Issues and PRs are welcome, especially new test runners for the trimming allowlist, better failure patterns and audit checks. Run `claude plugin validate .` before opening a PR.

## License

MIT
