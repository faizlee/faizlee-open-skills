For /relay [pair], do not inspect .ai-relay files manually and do not compare LastWriteTime yourself.

Always delegate state handling to the user-level Agent Workloop relay script. It already checks, in order:

1. unread codex-reply.md
2. unread cc-inbox.md
3. cc-report.md waiting for Codex decision
4. idle state

Run exactly this from the current project root:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-cc.ps1" -Pair "$ARGUMENTS" -Mode auto

Interpret the machine-readable status first:

- `AI_RELAY_STATUS=CODEX_REPLY_UNREAD`: read and follow the Codex reply printed by the script.
- `AI_RELAY_STATUS=CC_INBOX_UNREAD`: read and execute the task printed by the script.
- `AI_RELAY_STATUS=WAITING_FOR_CODEX`: a report is newer than the reply; wait or run report if it has not been sent.
- `AI_RELAY_STATUS=IDLE`: no new message and no unread decision; do not claim it is waiting for Codex.

Only if the script explicitly says the current task is complete and a report is needed, write the compressed report to .ai-relay/pairs/<pair>/cc-report.md, then run:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-cc.ps1" -Pair "$ARGUMENTS" -Mode report

Do not start Codex subagents, do not start codex-with-cc, and do not write into another pair directory.
