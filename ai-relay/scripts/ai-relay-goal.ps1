param(
  [string]$Pair,
  [string]$Goal,
  [int]$MaxRounds = 5,
  [ValidateSet('start','status','stop','summary')][string]$Mode = 'start',
  [string]$Reason = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

function Get-GoalPath {
  param([string]$PairDir)
  Join-Path $PairDir 'goal.json'
}

function Read-GoalState {
  param([string]$PairDir)
  $path = Get-GoalPath $PairDir
  if (Test-Path -LiteralPath $path) {
    return (Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json)
  }
  return $null
}

function Write-GoalState {
  param([string]$PairDir, $State)
  Write-AiRelayJson $State (Get-GoalPath $PairDir)
}

function Read-ReplyDecision {
  param([string]$Reply)
  if ($Reply -match '## 1\. 验收判断\s*[\r\n]+([^\r\n]+)') {
    return $Matches[1].Trim()
  }
  if ($Reply -match '接受本轮|裁决\s*[\r\n]+接受|验收判断\s*[\r\n]+接受') { return '接受' }
  if ($Reply -match '不接受') { return '不接受' }
  if ($Reply -match '部分接受') { return '部分接受' }
  return '无法判断'
}

function Read-NextInstruction {
  param([string]$Reply)
  $patterns = @(
    '## 4\. 给 Claude Code 的下一轮指令\s*([\s\S]*?)(?=\r?\n## 5\.|\z)',
    '## 下一步\s*([\s\S]*?)(?=\r?\n## |\z)',
    '## 给 Claude Code 的下一轮指令\s*([\s\S]*?)(?=\r?\n## |\z)'
  )
  foreach ($pattern in $patterns) {
    $m = [regex]::Match($Reply, $pattern)
    if ($m.Success) {
      $text = $m.Groups[1].Value.Trim()
      if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    }
  }
  return ''
}

function Test-GoalDone {
  param([string]$Reply, [string]$Decision, [string]$NextInstruction)
  if ($Decision -match '^接受' -and ($Reply -match '本轮完成|完成|不需要返工|不需要继续')) { return $true }
  if ([string]::IsNullOrWhiteSpace($NextInstruction) -and $Decision -match '^接受') { return $true }
  if ($NextInstruction -match '无|不需要|无需|停止|完成') { return $true }
  return $false
}

$projectRoot = Get-AiRelayProjectRoot
$pairId = Get-AiRelayPairId -ProjectRoot $projectRoot -Pair $Pair
Assert-AiRelayPairName $pairId
$pairDir = Get-AiRelayPairDir $projectRoot $pairId
if (-not (Test-Path -LiteralPath $pairDir)) {
  throw "Pair not found: $pairDir"
}

$goalPath = Get-GoalPath $pairDir
$inboxPath = Join-Path $pairDir 'cc-inbox.md'
$replyPath = Join-Path $pairDir 'codex-reply.md'

switch ($Mode) {
  'start' {
    if ([string]::IsNullOrWhiteSpace($Goal)) {
      throw "Please provide -Goal when starting a goal loop."
    }
    $state = [ordered]@{
      pairId = $pairId
      goal = $Goal
      status = 'running'
      round = 0
      maxRounds = $MaxRounds
      startedAt = (Get-Date).ToString('o')
      updatedAt = (Get-Date).ToString('o')
      stopReason = ''
      lastDecision = ''
      lastNextInstruction = ''
    }
    Write-GoalState -PairDir $pairDir -State $state
    $task = @"
# CC Goal Task - $pairId

## Goal
$Goal

## Goal Loop Rules
- Execute the next smallest step toward the goal.
- After each execution round, write .ai-relay/pairs/$pairId/cc-report.md.
- The report must include verification results and conflict risk.
- Immediately call: ai-relay-cc.ps1 -Pair $pairId -Mode report.
- Read the Codex reply.
- If Codex gives a next instruction, execute it directly.
- Stop only when Codex accepts/completes the goal, max rounds is reached, or a stop condition is hit.
- Do not use subagents, codex-with-cc, or --last.

## Stop Conditions
- Codex accepts/completes the goal.
- Max rounds reached: $MaxRounds.
- Codex says no next step is needed.
- Codex reports conflict risk that requires user decision.
- Validation is impossible or unsafe.
"@
    Set-Content -LiteralPath $inboxPath -Value $task -Encoding utf8
    Add-AiRelayLog -PairDir $pairDir -Event 'goal-start' -Detail "Goal loop started. MaxRounds=$MaxRounds`n$Goal"
    [void](Copy-AiRelayText $task)
    Write-Output "AI_RELAY_GOAL_STATUS=STARTED"
    Write-Output "AI_RELAY_GOAL_PAIR=$pairId"
    Write-Output "AI_RELAY_GOAL_MAX_ROUNDS=$MaxRounds"
    Write-Output $task
  }
  'status' {
    $state = Read-GoalState $pairDir
    if (-not $state) {
      Write-Output "AI_RELAY_GOAL_STATUS=NOT_STARTED"
      Write-Host "当前 pair 没有 goal loop。"
      exit 0
    }
    $state | ConvertTo-Json -Depth 8
  }
  'stop' {
    $state = Read-GoalState $pairDir
    if (-not $state) {
      Write-Output "AI_RELAY_GOAL_STATUS=NOT_STARTED"
      exit 0
    }
    $state.status = 'stopped'
    $state.stopReason = if ($Reason) { $Reason } else { 'Stopped manually.' }
    $state.updatedAt = (Get-Date).ToString('o')
    Write-GoalState -PairDir $pairDir -State $state
    Add-AiRelayLog -PairDir $pairDir -Event 'goal-stop' -Detail $state.stopReason
    Write-Output "AI_RELAY_GOAL_STATUS=STOPPED"
    Write-Output "AI_RELAY_GOAL_STOP_REASON=$($state.stopReason)"
  }
  'summary' {
    $state = Read-GoalState $pairDir
    if (-not $state) {
      Write-Output "AI_RELAY_GOAL_STATUS=NOT_STARTED"
      exit 0
    }
    $reply = Read-AiRelayTextFile $replyPath
    $decision = Read-ReplyDecision $reply
    $next = Read-NextInstruction $reply
    $state.lastDecision = $decision
    $state.lastNextInstruction = $next
    $state.updatedAt = (Get-Date).ToString('o')
    if (Test-GoalDone -Reply $reply -Decision $decision -NextInstruction $next) {
      $state.status = 'completed'
      $state.stopReason = 'Codex accepted/completed the goal.'
    } elseif ([int]$state.round -ge [int]$state.maxRounds) {
      $state.status = 'stopped'
      $state.stopReason = 'Max rounds reached.'
    } else {
      $state.status = 'running'
    }
    Write-GoalState -PairDir $pairDir -State $state

    $summaryDir = Join-Path $pairDir 'goal'
    New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null
    $summaryPath = Join-Path $summaryDir ("goal-summary-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".md")
    $summary = @"
# AI Relay Goal Summary

- Pair: `$pairId`
- Status: `$($state.status)`
- Round: `$($state.round)` / `$($state.maxRounds)`
- Decision: `$decision`
- Stop reason: `$($state.stopReason)`

## Goal
$($state.goal)

## Last Next Instruction
$next
"@
    Set-Content -LiteralPath $summaryPath -Value $summary -Encoding utf8
    Write-Output "AI_RELAY_GOAL_STATUS=$($state.status.ToString().ToUpperInvariant())"
    Write-Output "AI_RELAY_GOAL_SUMMARY=$summaryPath"
    Write-Output $summary
  }
}
