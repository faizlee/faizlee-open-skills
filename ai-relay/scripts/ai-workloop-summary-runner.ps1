param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$Pair,
  [ValidateSet('cc','codex','local')][string]$Analyzer = 'cc',
  [switch]$UseCache,
  [switch]$CacheOnly,
  [switch]$Open,
  [string]$StdoutPath = '',
  [string]$StderrPath = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

function Write-SummaryRunnerStatus {
  param(
    [string]$Status,
    [string]$Message,
    $ExitCode = 0
  )
  $exitCodeValue = 0
  if ($ExitCode -is [int]) {
    $exitCodeValue = $ExitCode
  } elseif ([string]$ExitCode -match '^-?\d+$') {
    $exitCodeValue = [int]$ExitCode
  }
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    projectRoot = $ProjectRoot
    analyzer = $Analyzer
    status = $Status
    message = $Message
    exitCode = $exitCodeValue
    updatedAt = (Get-Date).ToString('o')
    processId = $PID
    outputPath = $script:outputPath
    stdoutPath = $script:stdoutPath
    stderrPath = $script:stderrPath
    summaryMdPath = $script:summaryMdPath
    summaryHtmlPath = $script:summaryHtmlPath
  }) $script:statusPath
}

Push-Location $ProjectRoot
try {
  Assert-AiRelayPairName $Pair
  $pairDir = Get-AiRelayPairDir $ProjectRoot $Pair
  if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair not found: $pairDir" }

  $summaryDir = Join-Path (Join-Path $pairDir 'summary') $Analyzer
  New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null
  $script:statusPath = Join-Path $pairDir 'summary-runner-status.json'
  $script:outputPath = Join-Path $pairDir 'summary-runner-output.md'
  $script:stdoutPath = if ([string]::IsNullOrWhiteSpace($StdoutPath)) { Join-Path $pairDir 'summary-runner-process.stdout.log' } else { $StdoutPath }
  $script:stderrPath = if ([string]::IsNullOrWhiteSpace($StderrPath)) { Join-Path $pairDir 'summary-runner-process.stderr.log' } else { $StderrPath }
  $script:summaryMdPath = Join-Path $summaryDir 'workloop-summary-latest.md'
  $script:summaryHtmlPath = Join-Path $summaryDir 'workloop-summary-latest.html'

  $startText = @"
AI_WORKLOOP_SUMMARY_RUNNER_STATUS=RUNNING
startedAt=$(Get-Date -Format o)
pair=$Pair
project=$ProjectRoot
analyzer=$Analyzer

Running ai-workloop-summary.ps1.

"@
  Set-Content -LiteralPath $script:outputPath -Value $startText -Encoding utf8
  Write-SummaryRunnerStatus -Status 'running' -Message 'Running pair summary.'

  $summaryArgs = @{
    Pair = $Pair
    Analyzer = $Analyzer
    Format = 'both'
  }
  if ($UseCache) { $summaryArgs.UseCache = $true }
  if ($CacheOnly) { $summaryArgs.CacheOnly = $true }
  if ($Open) { $summaryArgs.Open = $true }

  Write-Output "AI_WORKLOOP_SUMMARY_RUNNER_PAIR=$Pair"
  Write-Output "AI_WORKLOOP_SUMMARY_RUNNER_ANALYZER=$Analyzer"
  Write-Output "AI_WORKLOOP_SUMMARY_RUNNER_OUTPUT=$script:outputPath"
  Write-Output ''

  $global:LASTEXITCODE = 0
  & "$PSScriptRoot\ai-workloop-summary.ps1" @summaryArgs 2>&1 | ForEach-Object {
    $line = [string]$_
    Add-Content -LiteralPath $script:outputPath -Value $line -Encoding utf8
    Write-Output $line
  }
  $exitCode = $LASTEXITCODE
  if ($null -eq $exitCode) { $exitCode = 0 }

  if ($exitCode -ne 0) {
    Write-SummaryRunnerStatus -Status 'failed' -Message "Pair summary failed. ExitCode=$exitCode" -ExitCode $exitCode
    exit $exitCode
  }

  Write-SummaryRunnerStatus -Status 'completed' -Message 'Pair summary completed.'
  Write-Output ''
  Write-Output 'AI_WORKLOOP_SUMMARY_RUNNER_STATUS=COMPLETED'
  exit 0
} catch {
  $message = $_.Exception.Message
  try {
    if ($script:outputPath) {
      Add-Content -LiteralPath $script:outputPath -Value "ERROR: $message" -Encoding utf8
    }
    Write-SummaryRunnerStatus -Status 'failed' -Message $message -ExitCode 1
  } catch {
  }
  Write-Error $message
  exit 1
} finally {
  Pop-Location
}
