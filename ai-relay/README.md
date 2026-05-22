# Agent Workloop

Agent collaboration loop for Claude Code + Codex, with a lightweight file relay underneath.

For full documentation, see [README.zh-CN.md](./README.zh-CN.md).

## What It Does

- Installs once under `$HOME\.ai-tools`.
- Stores per-project data under `.ai-relay/pairs/<pair>/`.
- Binds one pair to one explicit Codex session id and one Claude Code session.
- Uses a lightweight relay to pass Codex instructions to Claude Code through files.
- Relays compressed Claude Code reports back to Codex for review.
- Claude Code auto relay checks unread Codex replies, unread inbox messages, and waiting-for-decision state.
- `/workloop` is the single Claude Code command: without a goal it checks message state; with a goal it starts the review loop.
- Workloop sends each completed Claude Code round to Codex, updates `goal.json`, and continues when Codex gives a next instruction.
- Static dashboard summarizes projects, pairs, workloop status, latest reports, and latest Codex decisions.
- Archives every report round and exports Chinese Markdown/HTML audit reports.

## Hard Boundaries

- No `--last`.
- No subagents.
- No codex-with-cc.
- No daemon.
- No terminal/window injection.
- No automatic business-code changes.

## Install

```powershell
.\install.ps1
```

## Quick Commands

```powershell
ai-relay-bind-cc.ps1 -Pair <pair>
ai-workloop.ps1 <pair> [goal...]
ai-workloop-dashboard.ps1 -ProjectRoot <path> -Open
ai-relay-bind-codex.ps1 -Pair <pair> -CodexSessionId <id>
ai-relay-codex.ps1 -Pair <pair> -Message "<message>"
ai-relay-cc.ps1 -Pair <pair> -Mode report
ai-relay-export.ps1 -Pair <pair> -Format both
ai-relay-review.ps1 -Pair <pair> -Format both
ai-relay-goal.ps1 -Pair <pair> -Goal "<goal>" -MaxRounds 5
```

Claude Code slash commands:

```text
/bind <pair>
/workloop <pair> [goal]
```

## Verify

```powershell
.\tests\verify.ps1
```
