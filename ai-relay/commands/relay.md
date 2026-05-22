For /relay [pair], do not inspect .ai-relay files manually and do not compare LastWriteTime yourself.

Always delegate state handling to the user-level AI Relay script. It already checks, in order:

1. unread codex-reply.md
2. unread cc-inbox.md
3. cc-report.md waiting for Codex decision
4. idle state

Run exactly this from the current project root:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-cc.ps1" -Pair "$ARGUMENTS" -Mode auto

Only if the script explicitly says the current task is complete and a report is needed, write the compressed report to .ai-relay/pairs/<pair>/cc-report.md, then run:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-cc.ps1" -Pair "$ARGUMENTS" -Mode report

Do not start Codex subagents, do not start codex-with-cc, and do not write into another pair directory.
