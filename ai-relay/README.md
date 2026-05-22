# AI Relay

Lightweight user-level relay for Codex / Claude Code pairs in the same project.

For full documentation, see [README.zh-CN.md](./README.zh-CN.md).

## What It Does

- Installs once under `$HOME\.ai-tools`.
- Stores per-project data under `.ai-relay/pairs/<pair>/`.
- Binds one pair to one explicit Codex session id and one Claude Code session.
- Relays Codex instructions to Claude Code through files.
- Relays compressed Claude Code reports back to Codex.
- Claude Code auto relay checks unread Codex replies, unread inbox messages, and waiting-for-decision state.
- Goal loop sends each completed Claude Code round to Codex, updates `goal.json`, and continues when Codex gives a next instruction.
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
ai-relay-bind-codex.ps1 -Pair <pair> -CodexSessionId <id>
ai-relay-codex.ps1 -Pair <pair> -Message "<message>"
ai-relay-cc.ps1 -Pair <pair> -Mode report
ai-relay-export.ps1 -Pair <pair> -Format both
ai-relay-review.ps1 -Pair <pair> -Format both
ai-relay-goal.ps1 -Pair <pair> -Goal "<goal>" -MaxRounds 5
```

## Verify

```powershell
.\tests\verify.ps1
```
