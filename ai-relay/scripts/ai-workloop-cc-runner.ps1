param(
  [Parameter(Mandatory=$true)][string]$Pair,
  [ValidateSet('inbox','reply')][string]$Source = 'inbox',
  [ValidateSet('default','acceptEdits','auto','dontAsk','plan')][string]$PermissionMode = 'default',
  [decimal]$MaxBudgetUsd = 0.50,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

$projectRoot = Get-AiRelayProjectRoot
$pairId = Get-AiRelayPairId -ProjectRoot $projectRoot -Pair $Pair
Assert-AiRelayPairName $pairId
$pairDir = Get-AiRelayPairDir $projectRoot $pairId
if (-not (Test-Path -LiteralPath $pairDir)) {
  throw "Pair not found: $pairDir"
}

$outPath = Join-Path $pairDir 'cc-runner-output.md'
$statusPath = Join-Path $pairDir 'cc-runner-status.json'

function Write-CcRunnerStatus {
  param(
    [Parameter(Mandatory=$true)][string]$Status,
    [string]$Message = '',
    [int]$ExitCode = 0
  )
  Write-AiRelayJson ([ordered]@{
    pairId = $pairId
    projectRoot = $projectRoot
    status = $Status
    message = $Message
    exitCode = $ExitCode
    outputPath = $outPath
    updatedAt = (Get-Date).ToString('o')
    processId = $PID
  }) $statusPath
}

$pairJson = Read-AiRelayPairJson $pairDir
$ccSessionId = [string]$pairJson.ccSessionId
if ([string]::IsNullOrWhiteSpace($ccSessionId)) {
  Write-CcRunnerStatus -Status 'failed' -Message 'pair.json does not contain ccSessionId.' -ExitCode 1
  throw "pair.json does not contain ccSessionId. Re-bind from Claude Code with ai-relay-bind-cc.ps1 -Pair $pairId -CcSessionId <claude-session-id> -Force, then bind Codex again."
}

$sourcePath = if ($Source -eq 'reply') { Join-Path $pairDir 'codex-reply.md' } else { Join-Path $pairDir 'cc-inbox.md' }
$sourceText = Read-AiRelayTextFile $sourcePath
if ([string]::IsNullOrWhiteSpace($sourceText)) {
  Write-CcRunnerStatus -Status 'failed' -Message "$Source source is empty: $sourcePath" -ExitCode 1
  throw "$Source source is empty: $sourcePath"
}

$prompt = @"
You are the Claude Code execution agent for Agent Workloop pair "$pairId".

Project root:
$projectRoot

Read the task below, execute only what is requested, then write a compressed report to:
.ai-relay/pairs/$pairId/cc-report.md

Report requirements:
- Use the existing CC Report format.
- Include changed files and verification commands.
- Do not paste long logs or full diffs.
- If execution is unsafe or unclear, write that in the report instead of guessing.
- Do not auto-push unless the task explicitly asks.

Task:
$sourceText
"@

$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) {
  Write-CcRunnerStatus -Status 'failed' -Message 'claude CLI not found in PATH.' -ExitCode 1
  throw "claude CLI not found in PATH."
}

$args = @('--print', '--resume', $ccSessionId, '--permission-mode', $PermissionMode, '--max-budget-usd', ([string]$MaxBudgetUsd), $prompt)

Write-Output "AI_WORKLOOP_CC_RUNNER_PAIR=$pairId"
Write-Output "AI_WORKLOOP_CC_RUNNER_SESSION=$ccSessionId"
Write-Output "AI_WORKLOOP_CC_RUNNER_SOURCE=$sourcePath"
Write-Output "AI_WORKLOOP_CC_RUNNER_OUTPUT=$outPath"

if ($DryRun) {
  Write-CcRunnerStatus -Status 'dry-run' -Message 'Dry run completed.'
  Write-Output "AI_WORKLOOP_CC_RUNNER_DRYRUN=1"
  Write-Output "claude --print --resume <ccSessionId> --permission-mode $PermissionMode --max-budget-usd $MaxBudgetUsd <prompt>"
  exit 0
}

Add-AiRelayLog -PairDir $pairDir -Event 'cc-runner-start' -Detail "Running Claude Code runner. Source=$Source PermissionMode=$PermissionMode MaxBudgetUsd=$MaxBudgetUsd"
Write-CcRunnerStatus -Status 'running' -Message "Claude Code runner started. Source=$Source PermissionMode=$PermissionMode MaxBudgetUsd=$MaxBudgetUsd"
Push-Location $projectRoot
try {
  $startText = @"
AI_WORKLOOP_CC_RUNNER_STATUS=RUNNING
startedAt=$(Get-Date -Format o)
pair=$pairId
source=$sourcePath
claudeSessionId=$ccSessionId

Claude CLI is running in --print mode. Some Claude CLI versions do not stream partial stdout, so this file may stay unchanged until the command finishes.

"@
  Set-Content -LiteralPath $outPath -Value $startText -Encoding utf8
  $outputLines = & $claude.Source @args 2>&1 | Tee-Object -FilePath $outPath
  $exitCode = $LASTEXITCODE
  $output = $outputLines | Out-String
  if ($exitCode -ne 0) {
    Add-AiRelayLog -PairDir $pairDir -Event 'cc-runner-failed' -Detail "ExitCode=$exitCode`n$output"
    Write-CcRunnerStatus -Status 'failed' -Message "claude runner failed. Output written to $outPath" -ExitCode $exitCode
    throw "claude runner failed with exit code $exitCode. Output written to $outPath"
  }
} finally {
  Pop-Location
}

Add-AiRelayLog -PairDir $pairDir -Event 'cc-runner-completed' -Detail "Output written to $outPath"
Write-CcRunnerStatus -Status 'completed' -Message "Claude Code runner completed. Output written to $outPath"
Write-Output "AI_WORKLOOP_CC_RUNNER_STATUS=COMPLETED"
Write-Output (Read-AiRelayTextFile $outPath)
