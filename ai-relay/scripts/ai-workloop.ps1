param(
  [Parameter(Position=0)][string]$Pair,
  [Parameter(Position=1, ValueFromRemainingArguments=$true)][string[]]$GoalParts,
  [int]$MaxRounds = 10
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

$goal = ''
if ($GoalParts) {
  $goal = ($GoalParts -join ' ').Trim()
}

if ([string]::IsNullOrWhiteSpace($Pair)) {
  & "$PSScriptRoot\ai-relay-cc.ps1" -Mode auto
  exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($goal)) {
  $projectRoot = Get-AiRelayProjectRoot
  $pairId = Get-AiRelayPairId -ProjectRoot $projectRoot -Pair $Pair
  Assert-AiRelayPairName $pairId
  $pairDir = Get-AiRelayPairDir $projectRoot $pairId
  $reportPath = Join-Path $pairDir 'cc-report.md'
  $replyPath = Join-Path $pairDir 'codex-reply.md'

  if (Test-Path -LiteralPath $reportPath) {
    $report = Read-AiRelayTextFile $reportPath
    $hasReport = -not [string]::IsNullOrWhiteSpace($report)
    $replyMissing = -not (Test-Path -LiteralPath $replyPath)
    $reportIsNewer = $false
    if (-not $replyMissing) {
      $reportIsNewer = (Get-Item -LiteralPath $reportPath).LastWriteTime -gt (Get-Item -LiteralPath $replyPath).LastWriteTime
    }
    if ($hasReport -and ($replyMissing -or $reportIsNewer)) {
      Write-Output "AI_WORKLOOP_STATUS=REPORT_READY"
      Write-Output "AI_WORKLOOP_ACTION=SEND_REPORT_TO_CODEX"
      & "$PSScriptRoot\ai-relay-cc.ps1" -Pair $Pair -Mode report
      exit $LASTEXITCODE
    }
  }

  & "$PSScriptRoot\ai-relay-cc.ps1" -Pair $Pair -Mode auto
  exit $LASTEXITCODE
}

& "$PSScriptRoot\ai-relay-goal.ps1" -Pair $Pair -Goal $goal -MaxRounds $MaxRounds -Mode start
exit $LASTEXITCODE
