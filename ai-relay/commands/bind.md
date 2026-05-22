Use the user-level Agent Workloop relay script, not a project-local .ai-relay script.

Run this from the current project root:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-bind-cc.ps1" -Pair "$ARGUMENTS"

If the current Claude Code session id is available, include it:

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-bind-cc.ps1" -Pair "<pair>" -CcSessionId "<current Claude Code session id>"

This script writes .ai-relay/pairs/<pair>/bind-request.md and copies its content to the clipboard.

Then tell the user:
- If Codex is in the same project workspace, it can read .ai-relay/pairs/<pair>/bind-request.md directly.
- Otherwise, paste the clipboard content into the matching Codex session.
- In Codex, run /bind <pair>.
