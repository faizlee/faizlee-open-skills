param(
  [Parameter(Mandatory=$true)][string]$Pair,
  [ValidateSet('inbox','reply')][string]$Source = 'inbox',
  [ValidateSet('default','acceptEdits','auto','dontAsk','plan')][string]$PermissionMode = 'default',
  [Nullable[decimal]]$MaxBudgetUsd = $null,
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
$streamPath = Join-Path $pairDir 'cc-runner-stream.jsonl'
$statusPath = Join-Path $pairDir 'cc-runner-status.json'

function Write-CcRunnerStatus {
  param(
    [Parameter(Mandatory=$true)][string]$Status,
    [string]$Message = '',
    [int]$ExitCode = 0
  )
  $existingStatus = $null
  if (Test-Path -LiteralPath $statusPath) {
    try {
      $existingStatus = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
      $existingStatus = $null
    }
  }
  Write-AiRelayJson ([ordered]@{
    pairId = $pairId
    projectRoot = $projectRoot
    status = $Status
    message = $Message
    exitCode = $ExitCode
    outputPath = $outPath
    streamPath = $streamPath
    stdoutPath = if ($existingStatus -and $existingStatus.stdoutPath) { [string]$existingStatus.stdoutPath } else { '' }
    stderrPath = if ($existingStatus -and $existingStatus.stderrPath) { [string]$existingStatus.stderrPath } else { '' }
    updatedAt = (Get-Date).ToString('o')
    processId = $PID
  }) $statusPath
}

function Get-JsonTextFragments {
  param(
    $Value,
    [string]$Name = ''
  )
  $items = @()
  if ($null -eq $Value) {
    return $items
  }
  if ($Value -is [string]) {
    if ($Name -match '^(text|result|message|error)$' -and -not [string]::IsNullOrWhiteSpace($Value)) {
      return @($Value)
    }
    return $items
  }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    foreach ($entry in $Value) {
      $items += Get-JsonTextFragments -Value $entry -Name $Name
    }
    return $items
  }
  $props = $Value.PSObject.Properties
  foreach ($prop in $props) {
    $items += Get-JsonTextFragments -Value $prop.Value -Name $prop.Name
  }
  return $items
}

function Convert-StreamJsonLineToText {
  param([string]$Line)
  if ([string]::IsNullOrWhiteSpace($Line)) {
    return ''
  }
  try {
    $obj = $Line | ConvertFrom-Json
    $type = if ($obj.type) { [string]$obj.type } else { 'event' }
    if ($type -eq 'stream_event' -and $obj.event) {
      $eventType = [string]$obj.event.type
      if ($eventType -eq 'content_block_delta' -and $obj.event.delta) {
        if ($obj.event.delta.text) {
          return [string]$obj.event.delta.text
        }
        if ($obj.event.delta.thinking) {
          return [string]$obj.event.delta.thinking
        }
        if ($obj.event.delta.partial_json) {
          return "[tool input] $($obj.event.delta.partial_json)"
        }
      }
      if ($eventType -eq 'content_block_start' -and $obj.event.content_block) {
        $block = $obj.event.content_block
        if ($block.type -eq 'tool_use') {
          return "[tool] $($block.name) started"
        }
        return "[$eventType] $($block.type)"
      }
      if ($eventType -eq 'message_delta' -and $obj.event.delta -and $obj.event.delta.stop_reason) {
        return "[message] stop_reason=$($obj.event.delta.stop_reason)"
      }
      if ($eventType -in @('content_block_stop','message_stop','message_start')) {
        return ''
      }
      return ''
    }
    if ($type -eq 'assistant' -and $obj.message -and $obj.message.content) {
      $parts = @()
      foreach ($content in @($obj.message.content)) {
        if ($content.type -eq 'text' -and $content.text) {
          $parts += [string]$content.text
        } elseif ($content.type -eq 'tool_use') {
          $toolInput = if ($content.input) { ($content.input | ConvertTo-Json -Depth 8 -Compress) } else { '' }
          $parts += "[tool] $($content.name) $toolInput"
        }
      }
      if ($parts.Count -gt 0) {
        return ($parts -join "`n")
      }
    }
    if ($type -eq 'system') {
      $subtype = if ($obj.subtype) { [string]$obj.subtype } else { 'system' }
      $summary = if ($obj.summary) { [string]$obj.summary } elseif ($obj.description) { [string]$obj.description } elseif ($obj.status) { [string]$obj.status } else { '' }
      if ($summary) {
        return "[system:$subtype] $summary"
      }
      return "[system:$subtype]"
    }
    if ($type -eq 'user' -and $obj.tool_use_result) {
      return "[tool result] $($obj.tool_use_result)"
    }
    if ($type -eq 'result') {
      $subtype = if ($obj.subtype) { [string]$obj.subtype } else { 'result' }
      $errorText = ''
      if ($obj.errors) {
        $errorText = (@($obj.errors) -join '; ')
      }
      $cost = if ($obj.total_cost_usd -ne $null) { " cost=$($obj.total_cost_usd)" } else { '' }
      $duration = if ($obj.duration_ms -ne $null) { " durationMs=$($obj.duration_ms)" } else { '' }
      if ($errorText) {
        return "[result:$subtype] $errorText$cost$duration"
      }
      return "[result:$subtype]$cost$duration"
    }
    $fragments = @(Get-JsonTextFragments -Value $obj | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($fragments.Count -gt 0) {
      return "[$type] " + ($fragments -join "`n")
    }
    if ($obj.type) {
      return "[$type]"
    }
  } catch {
  }
  return $Line
}

$pairJson = Read-AiRelayPairJson $pairDir
$ccSessionId = [string]$pairJson.ccSessionId

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

$args = @(
  '--print',
  '--permission-mode', $PermissionMode,
  '--verbose',
  '--output-format', 'stream-json',
  '--include-partial-messages',
  $prompt
)
if (-not [string]::IsNullOrWhiteSpace($ccSessionId)) {
  $args = @('--print', '--resume', $ccSessionId) + $args[1..($args.Count - 1)]
}
if ($MaxBudgetUsd -ne $null) {
  $args = @(
    '--print',
    '--permission-mode', $PermissionMode,
    '--max-budget-usd', ([string]$MaxBudgetUsd),
    '--verbose',
    '--output-format', 'stream-json',
    '--include-partial-messages',
    $prompt
  )
  if (-not [string]::IsNullOrWhiteSpace($ccSessionId)) {
    $args = @('--print', '--resume', $ccSessionId) + $args[1..($args.Count - 1)]
  }
}

Write-Output "AI_WORKLOOP_CC_RUNNER_PAIR=$pairId"
Write-Output "AI_WORKLOOP_CC_RUNNER_SESSION=$ccSessionId"
Write-Output "AI_WORKLOOP_CC_RUNNER_SOURCE=$sourcePath"
Write-Output "AI_WORKLOOP_CC_RUNNER_OUTPUT=$outPath"

if ($DryRun) {
  Write-CcRunnerStatus -Status 'dry-run' -Message 'Dry run completed.'
  Write-Output "AI_WORKLOOP_CC_RUNNER_DRYRUN=1"
  if ($MaxBudgetUsd -ne $null) {
    $resumeText = if ([string]::IsNullOrWhiteSpace($ccSessionId)) { '' } else { ' --resume <ccSessionId>' }
    Write-Output "claude --print$resumeText --permission-mode $PermissionMode --max-budget-usd $MaxBudgetUsd --verbose --output-format stream-json --include-partial-messages <prompt>"
  } else {
    $resumeText = if ([string]::IsNullOrWhiteSpace($ccSessionId)) { '' } else { ' --resume <ccSessionId>' }
    Write-Output "claude --print$resumeText --permission-mode $PermissionMode --verbose --output-format stream-json --include-partial-messages <prompt>"
  }
  exit 0
}

$budgetText = if ($MaxBudgetUsd -ne $null) { "MaxBudgetUsd=$MaxBudgetUsd" } else { "MaxBudgetUsd=unlimited" }
Add-AiRelayLog -PairDir $pairDir -Event 'cc-runner-start' -Detail "Running Claude Code runner. Source=$Source PermissionMode=$PermissionMode $budgetText"
Write-CcRunnerStatus -Status 'running' -Message "Claude Code runner started. Source=$Source PermissionMode=$PermissionMode $budgetText"
Push-Location $projectRoot
try {
  $startText = @"
AI_WORKLOOP_CC_RUNNER_STATUS=RUNNING
startedAt=$(Get-Date -Format o)
pair=$pairId
source=$sourcePath
claudeSessionId=$ccSessionId

Claude CLI is running with --verbose --output-format stream-json and --include-partial-messages.
Raw stream is written to:
$streamPath

"@
  Set-Content -LiteralPath $outPath -Value $startText -Encoding utf8
  Set-Content -LiteralPath $streamPath -Value '' -Encoding utf8
  $outputBuffer = New-Object System.Collections.Generic.List[string]
  & $claude.Source @args 2>&1 | ForEach-Object {
    $line = [string]$_
    Add-Content -LiteralPath $streamPath -Value $line -Encoding utf8
    $displayLine = Convert-StreamJsonLineToText -Line $line
    if (-not [string]::IsNullOrWhiteSpace($displayLine)) {
      Add-Content -LiteralPath $outPath -Value $displayLine -Encoding utf8
      Write-Output $displayLine
      [void]$outputBuffer.Add($displayLine)
    }
  }
  $exitCode = $LASTEXITCODE
  $output = $outputBuffer | Out-String
  if ($exitCode -ne 0) {
    Add-AiRelayLog -PairDir $pairDir -Event 'cc-runner-failed' -Detail "ExitCode=$exitCode`n$output"
    Write-CcRunnerStatus -Status 'failed' -Message "claude runner failed. Output written to $outPath" -ExitCode $exitCode
    throw "claude runner failed with exit code $exitCode. Output written to $outPath"
  }
} finally {
  Pop-Location
}

Add-AiRelayLog -PairDir $pairDir -Event 'cc-runner-completed' -Detail "Output written to $outPath"
$readPath = if ($Source -eq 'reply') { Join-Path $pairDir 'codex-reply.read.md' } else { Join-Path $pairDir 'cc-inbox.read.md' }
Set-Content -LiteralPath $readPath -Value $sourceText -Encoding utf8
Write-CcRunnerStatus -Status 'completed' -Message "Claude Code runner completed. Output written to $outPath"
Write-Output "AI_WORKLOOP_CC_RUNNER_STATUS=COMPLETED"
Write-Output (Read-AiRelayTextFile $outPath)
