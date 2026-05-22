param(
  [Parameter(Position=0)][string]$Pair,
  [Parameter(Position=1, ValueFromRemainingArguments=$true)][string[]]$GoalParts,
  [int]$MaxRounds = 5
)

$ErrorActionPreference = 'Stop'

$goal = ''
if ($GoalParts) {
  $goal = ($GoalParts -join ' ').Trim()
}

if ([string]::IsNullOrWhiteSpace($Pair)) {
  & "$PSScriptRoot\ai-relay-cc.ps1" -Mode auto
  exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($goal)) {
  & "$PSScriptRoot\ai-relay-cc.ps1" -Pair $Pair -Mode auto
  exit $LASTEXITCODE
}

& "$PSScriptRoot\ai-relay-goal.ps1" -Pair $Pair -Goal $goal -MaxRounds $MaxRounds -Mode start
exit $LASTEXITCODE
