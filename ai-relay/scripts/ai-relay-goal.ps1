param(
  [string]$Pair,
  [string]$Goal,
  [int]$MaxRounds = 10,
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

function New-GoalMaxRoundsStopReason {
  param($State, [string]$Decision, [string]$NextInstruction)
  $round = if ($State.round -ne $null) { [int]$State.round } else { 0 }
  $maxRounds = if ($State.maxRounds -ne $null) { [int]$State.maxRounds } else { 10 }
  $next = if ([string]::IsNullOrWhiteSpace($NextInstruction)) { '没有明确下一步，但目标也没有被判定完成。' } else { $NextInstruction.Trim() }
  if ($next.Length -gt 500) { $next = $next.Substring(0, 500) + '...' }
  @"
已达到最大轮次 $round/$maxRounds，Workloop 停止并等待用户介入。

可能卡住的原因：
- Codex 没有确认目标完成，或仍持续给出下一步。
- 最后验收判断：$Decision
- 最后下一步摘要：$next

建议：人工查看最新报告和裁决，确认是否接受当前结果；如果不接受，请把目标拆小或指定更窄的下一轮目标。
"@.Trim()
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
      throw "Please provide -Goal when starting an Agent Workloop."
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
# Agent Workloop Task - $pairId

## Goal
$Goal

## Workloop Rules
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
- Max rounds reached: $MaxRounds. 达到最大轮次后必须停止等待用户介入，并在报告/状态里说明为什么卡住。
- Codex says no next step is needed.
- Codex reports conflict risk that requires user decision.
- Validation is impossible or unsafe.
"@
    Set-Content -LiteralPath $inboxPath -Value $task -Encoding utf8
    Add-AiRelayLog -PairDir $pairDir -Event 'workloop-start' -Detail "Agent Workloop started. MaxRounds=$MaxRounds`n$Goal"
    [void](Copy-AiRelayText $task)
    Write-Output "AI_WORKLOOP_STATUS=STARTED"
    Write-Output "AI_WORKLOOP_PAIR=$pairId"
    Write-Output "AI_WORKLOOP_MAX_ROUNDS=$MaxRounds"
    Write-Output "AI_RELAY_GOAL_STATUS=STARTED"
    Write-Output "AI_RELAY_GOAL_PAIR=$pairId"
    Write-Output "AI_RELAY_GOAL_MAX_ROUNDS=$MaxRounds"
    Write-Output $task
  }
  'status' {
    $state = Read-GoalState $pairDir
    if (-not $state) {
      Write-Output "AI_WORKLOOP_STATUS=NOT_STARTED"
      Write-Output "AI_RELAY_GOAL_STATUS=NOT_STARTED"
      Write-Host "当前 pair 没有 Agent Workloop。"
      exit 0
    }
    $state | ConvertTo-Json -Depth 8
  }
  'stop' {
    $state = Read-GoalState $pairDir
    if (-not $state) {
      Write-Output "AI_WORKLOOP_STATUS=NOT_STARTED"
      Write-Output "AI_RELAY_GOAL_STATUS=NOT_STARTED"
      exit 0
    }
    $state.status = 'stopped'
    $state.stopReason = if ($Reason) { $Reason } else { 'Stopped manually.' }
    $state.updatedAt = (Get-Date).ToString('o')
    Write-GoalState -PairDir $pairDir -State $state
    Add-AiRelayLog -PairDir $pairDir -Event 'workloop-stop' -Detail $state.stopReason
    Write-Output "AI_WORKLOOP_STATUS=STOPPED"
    Write-Output "AI_WORKLOOP_STOP_REASON=$($state.stopReason)"
    Write-Output "AI_RELAY_GOAL_STATUS=STOPPED"
    Write-Output "AI_RELAY_GOAL_STOP_REASON=$($state.stopReason)"
  }
  'summary' {
    $state = Read-GoalState $pairDir
    if (-not $state) {
      Write-Output "AI_WORKLOOP_STATUS=NOT_STARTED"
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
      $state.stopReason = New-GoalMaxRoundsStopReason -State $state -Decision $decision -NextInstruction $next
    } else {
      $state.status = 'running'
    }
    Write-GoalState -PairDir $pairDir -State $state

    $summaryDir = Join-Path $pairDir 'goal'
    New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null
    $summaryPath = Join-Path $summaryDir ("goal-summary-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".md")
    $summary = @"
# Agent Workloop Summary

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
    Write-Output "AI_WORKLOOP_STATUS=$($state.status.ToString().ToUpperInvariant())"
    Write-Output "AI_WORKLOOP_SUMMARY=$summaryPath"
    Write-Output "AI_RELAY_GOAL_STATUS=$($state.status.ToString().ToUpperInvariant())"
    Write-Output "AI_RELAY_GOAL_SUMMARY=$summaryPath"
    Write-Output $summary
  }
}
