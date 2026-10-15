---
name: handoff
description: Write a compact handoff note for the current task so the user can /clear and pick up later in a fresh, small context instead of carrying the whole conversation.
disable-model-invocation: true
argument-hint: "[optional file path, default .claude/handoff.md]"
---

# Handoff

Write a handoff note so that a fresh session can continue this work without the current conversation.

Target file: `$ARGUMENTS` if given, otherwise `.claude/handoff.md` in the project root. Overwrite any previous handoff.

Write from what you already know in this conversation. Don't re-read files or rerun commands to gather it. Keep it under 40 lines, with no prose padding:

```markdown
# Handoff: <task in a few words>  (<date>)

## Goal
<1-2 lines: what done looks like>

## State
- Done: <what's finished, with file paths>
- In progress: <what's half-done, and exactly where it stopped>
- Not started: <remaining steps>

## Decisions
- <decision> because <reason>   (only the ones a newcomer would otherwise revisit)

## Key files
- `path/to/file.ts:120-180`: <why it matters>

## Next step
<the single next action, concrete enough to start without asking>

## Gotchas
- <commands that must be run a certain way, failing tests that are expected, env quirks>
```

Then tell the user in two lines:

1. The note is saved at `<path>`. Suggest adding it to `.gitignore` if it shouldn't be committed.
2. To continue: run `/clear`, then start with `@<path> continue from the next step`.
