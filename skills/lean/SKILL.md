---
name: lean
description: Token-lean way of working in Claude Code. Use proactively whenever the user mentions saving tokens, usage limits, cost, or a long or slow session, and before exploring a large codebase.
argument-hint: "[optional: what you're about to work on]"
---

# Lean mode

Work so that each request carries as little context as possible, without getting worse results. Apply all of this for the rest of the session. If the user named a task ($ARGUMENTS), plan it this way.

## Reading code

- Find before you read. Use Grep/Glob (or a code-intelligence/LSP tool if one is installed) to locate the symbol, then Read only that region with `offset`/`limit`. Read a whole file only when it is short or you need all of it.
- Never re-read a file you just wrote or edited; your edit is the current state.
- Skip generated and vendored content: lockfiles, `dist/`, `build/`, `.next/`, `coverage/`, minified bundles, snapshots, large fixtures.
- For "how does X work across the codebase" questions, send an Explore subagent and keep only its summary.

## Changing code

- Use targeted Edit calls. Don't rewrite a whole file to change a few lines.
- Batch related edits to the same file into one Edit when the strings are close together.
- Don't paste back code you just wrote into the reply.

## Running commands

- Prefer quiet or summary output: `-q`, `--silent`, `--reporter=dot`, `--quiet`, `git status -s`, `git log --oneline -n 20`, `git diff --stat` before a full diff.
- Bound long output: `| tail -n 40`, `| head -n 40`, `| grep -E "FAIL|Error"`. Run one failing test instead of the suite while iterating. Exception: when lean-tokens output trimming is on, run test, build and lint commands plainly, with no pipes or redirects. Trimming only applies to plain commands.
- Hand long test runs, log digging and docs lookups to a subagent and keep its summary.
- If lean-tokens output trimming is on, a trimmed run prints where the full log is. Grep that log instead of rerunning the command.

## Talking

- Lead with the answer or the change. No preamble, no restating the request, no recap of steps the user watched.
- Show only changed lines or a short diff, not whole files.
- On a large, ambiguous task, ask one sharp question before exploring.

## Suggest to the user when it fits (once, briefly)

- Switching to an unrelated task → `/clear` (it costs nothing). If they'll come back → `/lean-tokens:handoff` first.
- Long session still on the same task → `/compact <what to keep>`, e.g. `/compact keep the API contract and failing tests`.
- Routine edits on the most capable model → a lighter model via `/model`, and `/effort` lower for simple work.
- Unsure where tokens go → `/context` for the current window, `/usage` for the breakdown by skills, subagents and MCP servers.
- Config bloat (big CLAUDE.md, many MCP servers) → `/lean-tokens:audit`.
