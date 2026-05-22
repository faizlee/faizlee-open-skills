param()

$ErrorActionPreference = 'Stop'

$root = Join-Path $HOME '.ai-tools\ai-relay'
$sourceCodexSkill = Join-Path $root 'skills\codex-ai-relay\SKILL.md'
$sourceClaudeSkill = Join-Path $root 'skills\claude-relay\SKILL.md'
$sourceBindCommand = Join-Path $root 'commands\bind.md'
$sourceRelayCommand = Join-Path $root 'commands\relay.md'
$sourceGoalCommand = Join-Path $root 'commands\goal.md'

$codexSkillDir = Join-Path $HOME '.codex\skills\ai-relay'
$claudeSkillDir = Join-Path $HOME '.claude\skills\relay'
$claudeCommandsDir = Join-Path $HOME '.claude\commands'
$codexFallbackDir = Join-Path $root 'manual-install\codex-ai-relay'
$claudeFallbackDir = Join-Path $root 'manual-install\claude-relay'

function Copy-RelayFile {
  param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
  )
  if (-not (Test-Path -LiteralPath $Source)) {
    throw "Source file not found: $Source. Re-run ai-relay install.ps1."
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
  Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

if (Test-Path -LiteralPath (Split-Path -Parent $codexSkillDir)) {
  Copy-RelayFile -Source $sourceCodexSkill -Destination (Join-Path $codexSkillDir 'SKILL.md')
  Write-Host "Codex Skill installed: $(Join-Path $codexSkillDir 'SKILL.md')"
} else {
  Copy-RelayFile -Source $sourceCodexSkill -Destination (Join-Path $codexFallbackDir 'SKILL.md')
  Write-Host "Codex Skill fallback generated: $(Join-Path $codexFallbackDir 'SKILL.md')"
}

if (Test-Path -LiteralPath (Split-Path -Parent $claudeSkillDir)) {
  Copy-RelayFile -Source $sourceClaudeSkill -Destination (Join-Path $claudeSkillDir 'SKILL.md')
  Write-Host "Claude Code Skill installed: $(Join-Path $claudeSkillDir 'SKILL.md')"
} else {
  Copy-RelayFile -Source $sourceClaudeSkill -Destination (Join-Path $claudeFallbackDir 'SKILL.md')
  Write-Host "Claude Code Skill fallback generated: $(Join-Path $claudeFallbackDir 'SKILL.md')"
}

if (Test-Path -LiteralPath $claudeCommandsDir) {
  Copy-RelayFile -Source $sourceBindCommand -Destination (Join-Path $claudeCommandsDir 'bind.md')
  Copy-RelayFile -Source $sourceRelayCommand -Destination (Join-Path $claudeCommandsDir 'relay.md')
  if (Test-Path -LiteralPath $sourceGoalCommand) {
    Copy-RelayFile -Source $sourceGoalCommand -Destination (Join-Path $claudeCommandsDir 'goal.md')
  }
  Write-Host "Claude commands installed: $claudeCommandsDir"
} else {
  Write-Host "Claude commands directory not found, skipped: $claudeCommandsDir"
}
