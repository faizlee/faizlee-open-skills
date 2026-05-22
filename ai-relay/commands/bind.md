Use the user-level Agent Workloop relay script, not a project-local .ai-relay script.

Run this from the current project root:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-bind-cc.ps1" -Pair "$ARGUMENTS"

If the current Claude Code session id is available, include it:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-bind-cc.ps1" -Pair "<pair>" -CcSessionId "<current Claude Code session id>"

This script writes .ai-relay/pairs/<pair>/bind-request.md and copies its content to the clipboard.

For an existing pair that only needs a Claude Code session id added or refreshed, do not force-bind. Run:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-workloop-rebind-cc.ps1" -Pair "<pair>" -CcSessionId "<current Claude Code session id>"

This preserves cc-inbox.md, cc-report.md, codex-reply.md, pair history, and the existing codexSessionId.

Then tell the user:
- If Codex is in the same project workspace, it can read .ai-relay/pairs/<pair>/bind-request.md directly.
- Otherwise, paste the clipboard content into the matching Codex session.
- In Codex, run /bind <pair>.
