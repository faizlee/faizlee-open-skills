Use AI Relay Goal Loop. This is not plain relay.

Run from the current project root:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-goal.ps1" -Pair "$ARGUMENTS" -Goal "$ARGUMENTS" -MaxRounds 5

After the script prints the goal task, execute it. For every completed round:

1. Write `.ai-relay/pairs/<pair>/cc-report.md`.
2. Immediately run:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-cc.ps1" -Pair "<pair>" -Mode report

3. Read the Codex reply.
4. If Codex gives a next instruction, execute it directly without asking the user.
5. Stop only when Codex accepts/completes the goal or a stop condition is hit.

Do not use subagents, codex-with-cc, or --last.
