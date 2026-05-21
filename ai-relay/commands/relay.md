For /relay [pair], use the user-level AI Relay script, not a project-local .ai-relay script.

1. Run:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-cc.ps1" -Pair "$ARGUMENTS" -Mode auto

2. If there is no unread inbox and the current work is ready to report, write a compressed report to .ai-relay/pairs/<pair>/cc-report.md, then run:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-cc.ps1" -Pair "$ARGUMENTS" -Mode report

Do not start Codex subagents, do not start codex-with-cc, and do not write into another pair directory.
