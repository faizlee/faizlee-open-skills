param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$Pair,
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

function Write-WorkloopRunnerStatus {
  param(
    [string]$Status,
    [string]$Message,
    $ExitCode = 0,
    [string]$Phase = '',
    [string]$Route = '',
    [string]$NextAction = ''
  )
  $exitCodeValue = 0
  if ($ExitCode -is [int]) {
    $exitCodeValue = $ExitCode
  } elseif ([string]$ExitCode -match '^-?\d+$') {
    $exitCodeValue = [int]$ExitCode
  }
  $snapshot = Get-WorkloopRunnerSnapshot
  if ([string]::IsNullOrWhiteSpace($Phase)) { $Phase = [string]$snapshot.phase }
  if ([string]::IsNullOrWhiteSpace($Route)) { $Route = [string]$snapshot.route }
  if ([string]::IsNullOrWhiteSpace($NextAction)) { $NextAction = [string]$snapshot.nextAction }
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    projectRoot = $ProjectRoot
    status = $Status
    message = $Message
    exitCode = $exitCodeValue
    phase = $Phase
    route = $Route
    nextAction = $NextAction
    snapshot = $snapshot
    updatedAt = (Get-Date).ToString('o')
    processId = $PID
    outputPath = $script:outputPath
    stdoutPath = $script:stdoutPath
    stderrPath = $script:stderrPath
    reportPath = $script:reportPath
    promptPath = $script:promptPath
    replyPath = $script:replyPath
    inboxPath = $script:inboxPath
  }) $script:statusPath
}

function Get-WorkloopFileStamp {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
      exists = $true
      bytes = $item.Length
      lastWriteAt = $item.LastWriteTime.ToString('o')
      hasText = -not [string]::IsNullOrWhiteSpace((Read-AiRelayTextFile $Path))
    }
  }
  [ordered]@{
    exists = $false
    bytes = 0
    lastWriteAt = ''
    hasText = $false
  }
}

function Test-WorkloopRunnerUnread {
  param([string]$SourcePath, [string]$ReadPath)
  $source = Read-AiRelayTextFile $SourcePath
  if ([string]::IsNullOrWhiteSpace($source)) { return $false }
  if ((Test-Path -LiteralPath $ReadPath) -and (Test-Path -LiteralPath $SourcePath)) {
    if ((Get-Item -LiteralPath $ReadPath).LastWriteTime -ge (Get-Item -LiteralPath $SourcePath).LastWriteTime) {
      return $false
    }
  }
  $read = Read-AiRelayTextFile $ReadPath
  $normalizedSource = ($source -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  $normalizedRead = ($read -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  return ($normalizedSource -ne $normalizedRead)
}

function Get-WorkloopRunnerSnapshot {
  if (-not $script:pairDir) {
    return [ordered]@{
      phase = 'starting'
      route = 'starting'
      nextAction = '初始化 runner。'
    }
  }
  $reportPath = Join-Path $script:pairDir 'cc-report.md'
  $replyPath = Join-Path $script:pairDir 'codex-reply.md'
  $replyReadPath = Join-Path $script:pairDir 'codex-reply.read.md'
  $inboxPath = Join-Path $script:pairDir 'cc-inbox.md'
  $inboxReadPath = Join-Path $script:pairDir 'cc-inbox.read.md'
  $goalPath = Join-Path $script:pairDir 'goal.json'

  $report = Get-WorkloopFileStamp $reportPath
  $reply = Get-WorkloopFileStamp $replyPath
  $inbox = Get-WorkloopFileStamp $inboxPath
  $replyUnread = Test-WorkloopRunnerUnread -SourcePath $replyPath -ReadPath $replyReadPath
  $inboxUnread = Test-WorkloopRunnerUnread -SourcePath $inboxPath -ReadPath $inboxReadPath
  $reportReady = $false
  if ($report.hasText) {
    if (-not $reply.exists) {
      $reportReady = $true
    } else {
      $reportReady = (Get-Item -LiteralPath $reportPath).LastWriteTime -gt (Get-Item -LiteralPath $replyPath).LastWriteTime
    }
  }

  $goalStatus = ''
  $goalRound = ''
  $goalMaxRounds = ''
  if (Test-Path -LiteralPath $goalPath) {
    try {
      $goal = Get-Content -LiteralPath $goalPath -Raw -Encoding utf8 | ConvertFrom-Json
      if ($goal.status) { $goalStatus = [string]$goal.status }
      if ($goal.round -ne $null) { $goalRound = [string]$goal.round }
      if ($goal.maxRounds -ne $null) { $goalMaxRounds = [string]$goal.maxRounds }
    } catch {
    }
  }

  $phase = 'idle'
  $route = 'idle'
  $nextAction = '当前没有待处理消息。'
  if ($goalStatus -eq 'completed') {
    $phase = 'completed'
    $route = 'goal completed'
    $nextAction = '目标已完成，可以查看总结或归档 pair。'
  } elseif ($goalStatus -eq 'stopped') {
    $phase = 'needs_user'
    $route = 'goal stopped'
    $nextAction = 'Workloop 已停止，需要人工判断下一步。'
  } elseif ($reportReady) {
    $phase = 'codex_review'
    $route = 'cc-report.md -> Codex'
    $nextAction = '把 cc-report.md 送给绑定的 Codex session 裁决。'
  } elseif ($replyUnread) {
    $phase = 'cc_followup'
    $route = 'codex-reply.md -> Claude Code'
    $nextAction = '让 Claude Code 读取并执行 Codex 裁决。'
  } elseif ($inboxUnread) {
    $phase = 'cc_execute'
    $route = 'cc-inbox.md -> Claude Code'
    $nextAction = '让 Claude Code 拉取并执行未读任务。'
  }

  [ordered]@{
    phase = $phase
    route = $route
    nextAction = $nextAction
    reportReady = $reportReady
    replyUnread = $replyUnread
    inboxUnread = $inboxUnread
    goalStatus = $goalStatus
    goalRound = $goalRound
    goalMaxRounds = $goalMaxRounds
    files = [ordered]@{
      report = $report
      reply = $reply
      inbox = $inbox
    }
  }
}

function Set-WorkloopRunnerPhaseFromOutput {
  param([string]$Line)
  if ($Line -match 'AI_WORKLOOP_STATUS=REPORT_READY|AI_WORKLOOP_ACTION=SEND_REPORT_TO_CODEX') {
    $script:phase = 'codex_review'
    $script:route = 'cc-report.md -> Codex'
    $script:nextAction = '正在调用 Codex 裁决 cc-report.md。'
    Write-WorkloopRunnerStatus -Status 'running' -Message '正在把 CC 报告送 Codex 裁决。' -Phase $script:phase -Route $script:route -NextAction $script:nextAction
  } elseif ($Line -match 'AI_RELAY_STATUS=CODEX_REPLY_UNREAD') {
    $script:phase = 'cc_followup'
    $script:route = 'codex-reply.md -> Claude Code'
    $script:nextAction = 'Codex 裁决已存在，下一步让 Claude Code 执行裁决。'
    Write-WorkloopRunnerStatus -Status 'running' -Message '检测到未读 Codex 裁决。' -Phase $script:phase -Route $script:route -NextAction $script:nextAction
  } elseif ($Line -match 'AI_RELAY_STATUS=CC_INBOX_UNREAD') {
    $script:phase = 'cc_execute'
    $script:route = 'cc-inbox.md -> Claude Code'
    $script:nextAction = 'Claude Code 需要执行 cc-inbox.md。'
    Write-WorkloopRunnerStatus -Status 'running' -Message '检测到未读 CC 任务。' -Phase $script:phase -Route $script:route -NextAction $script:nextAction
  } elseif ($Line -match 'AI_RELAY_STATUS=IDLE') {
    $script:phase = 'idle'
    $script:route = 'idle'
    $script:nextAction = '当前没有新的 Codex 指令或未读裁决。'
    Write-WorkloopRunnerStatus -Status 'running' -Message '状态机当前为空闲。' -Phase $script:phase -Route $script:route -NextAction $script:nextAction
  }
}

function Add-WorkloopRunnerLog {
  param([string]$Event, [string]$Detail)
  if (-not $script:pairDir) { return }
  $logPath = Join-Path $script:pairDir 'relay-log.md'
  $entry = @"

## $(Get-Date -Format o) - $Event
$Detail
"@
  Add-Content -LiteralPath $logPath -Value $entry -Encoding utf8
}

function Read-WorkloopGoalState {
  $goalPath = Join-Path $script:pairDir 'goal.json'
  if (-not (Test-Path -LiteralPath $goalPath)) { return $null }
  try {
    return Get-Content -LiteralPath $goalPath -Raw -Encoding utf8 | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-WorkloopGoalMaxRounds {
  param($Goal)
  if ($Goal -and $Goal.maxRounds -ne $null -and [string]$Goal.maxRounds -match '^\d+$') {
    return [int]$Goal.maxRounds
  }
  return 10
}

function New-WorkloopMaxRoundsStopReason {
  param($Goal, $Snapshot, [int]$Round, [int]$MaxRounds)
  $decision = if ($Goal -and $Goal.lastDecision) { [string]$Goal.lastDecision } else { '无最新裁决记录' }
  $next = if ($Goal -and $Goal.lastNextInstruction) { [string]$Goal.lastNextInstruction } else { '无明确下一步记录' }
  if ($next.Length -gt 500) { $next = $next.Substring(0, 500) + '...' }
  $phase = if ($Snapshot -and $Snapshot.phase) { [string]$Snapshot.phase } else { 'unknown' }
  $route = if ($Snapshot -and $Snapshot.route) { [string]$Snapshot.route } else { 'unknown' }
  $reportAt = if ($Snapshot -and $Snapshot.files -and $Snapshot.files.report -and $Snapshot.files.report.lastWriteAt) { [string]$Snapshot.files.report.lastWriteAt } else { '无报告时间' }
  $replyAt = if ($Snapshot -and $Snapshot.files -and $Snapshot.files.reply -and $Snapshot.files.reply.lastWriteAt) { [string]$Snapshot.files.reply.lastWriteAt } else { '无裁决时间' }
  @"
已达到最大轮次 $Round/$MaxRounds，Workloop 停止并等待用户介入。

可能卡住的原因：
- 多轮执行后 Codex 仍未确认目标完成，或仍持续给出下一步。
- 最后验收判断：$decision
- 最后下一步摘要：$next
- 停止时状态：phase=$phase，route=$route
- 最新报告时间：$reportAt
- 最新裁决时间：$replyAt

建议：
1. 打开最新 cc-report.md 和 codex-reply.md，确认是否其实已经达到目标。
2. 如果目标太大，把目标拆成更小的 pair 或重新设置更窄的最终目标。
3. 如果 Codex/CC 反复在同一问题上循环，人工指定下一轮只验证一个明确断点。
"@.Trim()
}

function Test-WorkloopGoalCompletedSignal {
  param($Goal)
  if (-not $Goal) { return $false }
  $decision = if ($Goal.lastDecision) { [string]$Goal.lastDecision } else { '' }
  $next = if ($Goal.lastNextInstruction) { [string]$Goal.lastNextInstruction } else { '' }
  if ($decision -notmatch '接受|完成|通过') { return $false }
  if ([string]::IsNullOrWhiteSpace($next)) { return $true }

  $normalizedNext = ($next -replace '\s+', ' ').Trim()
  $terminalSignal = $normalizedNext -match '无下一轮|无需下一轮|不需要下一轮|没有下一轮|不需要继续|无需继续|无需操作|无需执行|目标已完成|当前目标已完成|本目标已完成|本 pair 已完成|pair 已完成|停止|结束|关闭当前\s*pair|归档|等待用户|保持.*结束|当前 pair 已完成|不要再运行|不要继续'
  if (-not $terminalSignal) { return $false }

  $hasExecutableInstruction = $normalizedNext -match '请执行|执行|修改|清理|提交|纳入|完成后|返回压缩报告|运行|检查|修复|创建|更新|添加|增加|删除|写入|生成|验证|继续|推进|git\s+add|git\s+commit'
  if ($hasExecutableInstruction -and $normalizedNext -notmatch '不要继续|不需要继续|无需继续|无需执行|无需操作|不要再运行|停止|结束|等待.*提交|等待.*调度|保持.*结束') {
    return $false
  }
  if ($terminalSignal) {
    return $true
  }
  return $false
}

function Set-WorkloopGoalCompleted {
  param($Goal, [string]$Reason)
  if (-not $Goal) { return }
  $goalPath = Join-Path $script:pairDir 'goal.json'
  $Goal.status = 'completed'
  $Goal.stopReason = $Reason
  $Goal.updatedAt = (Get-Date).ToString('o')
  Write-AiRelayJson $Goal $goalPath
  Add-WorkloopRunnerLog -Event 'workloop-auto-completed' -Detail $Reason
}

function Write-WorkloopPlanPrompt {
  param($Goal)
  $goalText = if ($Goal -and $Goal.goal) { [string]$Goal.goal } else { '' }
  if ([string]::IsNullOrWhiteSpace($goalText)) {
    throw 'goal.json 中没有 goal，无法让 Codex 规划任务。'
  }
  $maxRounds = Get-WorkloopGoalMaxRounds -Goal $Goal
  $context = Read-AiRelayTextFile (Join-Path $script:pairDir 'context.md')
  $planPromptPath = Join-Path $script:pairDir 'codex-plan-prompt.md'
  $userGoalPath = Join-Path $script:pairDir 'user-goal.md'
  $userGoal = @"
# User Goal - $Pair

## Goal
$goalText

Max rounds: $maxRounds
"@
  Set-Content -LiteralPath $userGoalPath -Value $userGoal -Encoding utf8
  $prompt = @"
$context

# 用户目标
$goalText

# Codex 规划要求
你是此 pair 的 Codex 指挥线程。请根据用户目标、当前 pair 状态和最近裁决，生成给 Claude Code 的下一轮最小可执行任务。

必须遵守：
- 不使用 subagent。
- 不启动 codex-with-cc。
- 不使用 --last。
- 不把完整项目代码塞进 prompt。
- 只给 Claude Code 一个边界清晰、最小化、可执行的任务。
- 如果目标信息不足，让 Claude Code 做只读巡检并返回压缩事实。
- 如果上一轮已经满足目标，应明确说明不需要下一步，并建议结束。
- 如果可能与其他 pair 冲突，必须写入风险提醒。

固定输出：
## Workloop Decision
先输出一个 fenced JSON 代码块。只能使用以下四种 workloopDecision：
- continue：还需要 Claude Code 执行 nextTask。
- completed：目标已经完成，应该停止 pair。
- needs_user：需要用户裁决或补充目标。
- blocked：遇到阻塞，不能安全继续。

JSON 格式必须是：
```json
{
  "workloopDecision": "continue|completed|needs_user|blocked",
  "shouldWriteInbox": true,
  "reason": "一句话说明为什么",
  "nextTask": "如果 continue，这里写给 Claude Code 的完整任务；否则留空或写停止原因"
}
```

如果 workloopDecision 不是 continue，shouldWriteInbox 必须是 false。
只有 continue 才允许给 Claude Code 下发新任务。

## 给 Claude Code 的任务
写成 Claude Code 可直接执行的任务。
如果 workloopDecision 不是 continue，这一节只写“不下发新任务”。

## 规划理由
3-5 条。

## 冲突风险
说明可能冲突或无法判断。

## 额度控制
说明这一轮结束后是否需要回问 Codex。
"@
  Set-Content -LiteralPath $planPromptPath -Value $prompt -Encoding utf8
}

function Invoke-WorkloopChildScript {
  param(
    [Parameter(Mandatory=$true)][string]$ScriptName,
    [Parameter(Mandatory=$true)][string[]]$Arguments,
    [Parameter(Mandatory=$true)][string]$Label
  )
  $powershell = Get-Command pwsh -ErrorAction SilentlyContinue
  if (-not $powershell) { $powershell = Get-Command powershell -ErrorAction SilentlyContinue }
  if (-not $powershell) { throw 'PowerShell host not found.' }
  $scriptPath = Join-Path $PSScriptRoot $ScriptName
  if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Runner script not found: $scriptPath" }

  Write-Output ''
  Write-Output "AI_WORKLOOP_CHILD_START=$Label"
  Add-Content -LiteralPath $script:outputPath -Value "`n## $Label`n" -Encoding utf8
  Add-WorkloopRunnerLog -Event 'workloop-child-start' -Detail "$Label $ScriptName"

  $global:LASTEXITCODE = 0
  & $powershell.Source -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments 2>&1 | ForEach-Object {
    $line = [string]$_
    Add-Content -LiteralPath $script:outputPath -Value $line -Encoding utf8
    Set-WorkloopRunnerPhaseFromOutput -Line $line
    Write-Output $line
  }
  $exitCode = $LASTEXITCODE
  if ($null -eq $exitCode) { $exitCode = 0 }
  if ($exitCode -ne 0) {
    Add-WorkloopRunnerLog -Event 'workloop-child-failed' -Detail "$Label ExitCode=$exitCode"
    throw "$Label failed with exit code $exitCode."
  }
  Add-WorkloopRunnerLog -Event 'workloop-child-completed' -Detail "$Label completed."
  Write-Output "AI_WORKLOOP_CHILD_COMPLETED=$Label"
}

function Invoke-WorkloopAutomaticLoop {
  $safetyLimit = 50
  for ($i = 1; $i -le $safetyLimit; $i++) {
    $snapshot = Get-WorkloopRunnerSnapshot
    $goal = Read-WorkloopGoalState
    $goalStatus = if ($goal -and $goal.status) { [string]$goal.status } else { '' }
    $round = if ($goal -and $goal.round -ne $null -and [string]$goal.round -match '^\d+$') { [int]$goal.round } else { 0 }
    $maxRounds = Get-WorkloopGoalMaxRounds -Goal $goal
    Write-WorkloopRunnerStatus -Status 'running' -Message "自动循环第 $i 步：$($snapshot.phase)" -Phase ([string]$snapshot.phase) -Route ([string]$snapshot.route) -NextAction ([string]$snapshot.nextAction)

    if ($snapshot.phase -eq 'completed') {
      Write-Output "AI_WORKLOOP_LOOP_STOP=GOAL_COMPLETED"
      return
    }
    if ($snapshot.phase -eq 'needs_user' -or $goalStatus -eq 'stopped') {
      Write-Output "AI_WORKLOOP_LOOP_STOP=NEEDS_USER"
      return
    }
    if ($goal -and $round -ge $maxRounds) {
      $goal.status = 'stopped'
      $goal.stopReason = New-WorkloopMaxRoundsStopReason -Goal $goal -Snapshot $snapshot -Round $round -MaxRounds $maxRounds
      $goal.updatedAt = (Get-Date).ToString('o')
      Write-AiRelayJson $goal (Join-Path $script:pairDir 'goal.json')
      Write-Output "AI_WORKLOOP_LOOP_STOP=MAX_ROUNDS"
      Write-Output $goal.stopReason
      return
    }
    if ($goalStatus -in @('running','started','planned') -and (Test-WorkloopGoalCompletedSignal -Goal $goal)) {
      $reason = 'Codex 已接受结果，并明确不需要下一轮指令；Workloop 自动收口，避免空转。'
      Set-WorkloopGoalCompleted -Goal $goal -Reason $reason
      Write-Output "AI_WORKLOOP_LOOP_STOP=GOAL_COMPLETED_SIGNAL"
      Write-Output $reason
      return
    }

    if ($snapshot.reportReady) {
      $script:phase = 'codex_review'
      $script:route = 'cc-report.md -> Codex'
      $script:nextAction = '正在把 CC 报告送 Codex 裁决。'
      Write-WorkloopRunnerStatus -Status 'running' -Message '正在把 CC 报告送 Codex 裁决。' -Phase $script:phase -Route $script:route -NextAction $script:nextAction
      Invoke-WorkloopChildScript -ScriptName 'ai-relay-cc.ps1' -Arguments @('-Pair', $Pair, '-Mode', 'report') -Label 'Codex 审核 CC 报告'
      continue
    }

    if ($snapshot.replyUnread) {
      $script:phase = 'cc_followup'
      $script:route = 'codex-reply.md -> Claude Code'
      $script:nextAction = '正在让 Claude Code 执行 Codex 裁决。'
      Write-WorkloopRunnerStatus -Status 'running' -Message '正在让 Claude Code 执行 Codex 裁决。' -Phase $script:phase -Route $script:route -NextAction $script:nextAction
      Invoke-WorkloopChildScript -ScriptName 'ai-workloop-cc-runner.ps1' -Arguments @('-Pair', $Pair, '-Source', 'reply') -Label 'Claude Code 执行 Codex 裁决'
      continue
    }

    if ($snapshot.inboxUnread) {
      $script:phase = 'cc_execute'
      $script:route = 'cc-inbox.md -> Claude Code'
      $script:nextAction = '正在让 Claude Code 执行任务。'
      Write-WorkloopRunnerStatus -Status 'running' -Message '正在让 Claude Code 执行 cc-inbox.md。' -Phase $script:phase -Route $script:route -NextAction $script:nextAction
      Invoke-WorkloopChildScript -ScriptName 'ai-workloop-cc-runner.ps1' -Arguments @('-Pair', $Pair, '-Source', 'inbox') -Label 'Claude Code 执行任务'
      continue
    }

    if ($goal -and $goalStatus -in @('running','started','planned')) {
      $pairJson = Read-AiRelayPairJson $script:pairDir
      $codexSessionId = [string]$pairJson.codexSessionId
      if ([string]::IsNullOrWhiteSpace($codexSessionId)) {
        throw 'pair.json 缺少 codexSessionId，无法自动规划下一轮任务。'
      }
      Write-WorkloopPlanPrompt -Goal $goal
      $goalText = [string]$goal.goal
      $script:phase = 'codex_plan'
      $script:route = 'goal.json -> Codex -> cc-inbox.md'
      $script:nextAction = '正在让 Codex 规划给 Claude Code 的下一轮最小任务。'
      Write-WorkloopRunnerStatus -Status 'running' -Message '正在让 Codex 规划下一轮任务。' -Phase $script:phase -Route $script:route -NextAction $script:nextAction
      Invoke-WorkloopChildScript -ScriptName 'ai-workloop-plan-runner.ps1' -Arguments @('-ProjectRoot', $ProjectRoot, '-Pair', $Pair, '-CodexSessionId', $codexSessionId, '-Goal', $goalText, '-MaxRounds', [string]$maxRounds) -Label 'Codex 规划下一轮任务'
      continue
    }

    Write-Output "AI_WORKLOOP_LOOP_STOP=IDLE"
    return
  }
  throw "Workloop safety limit reached: $safetyLimit steps."
}

Push-Location $ProjectRoot
try {
  Assert-AiRelayPairName $Pair
  $pairDir = Get-AiRelayPairDir $ProjectRoot $Pair
  if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair not found: $pairDir" }
  $script:pairDir = $pairDir

  $script:statusPath = Join-Path $pairDir 'workloop-runner-status.json'
  $script:outputPath = Join-Path $pairDir 'workloop-runner-output.md'
  $script:stdoutPath = if ([string]::IsNullOrWhiteSpace($StdoutPath)) { Join-Path $pairDir 'workloop-runner-process.stdout.log' } else { $StdoutPath }
  $script:stderrPath = if ([string]::IsNullOrWhiteSpace($StderrPath)) { Join-Path $pairDir 'workloop-runner-process.stderr.log' } else { $StderrPath }
  $script:reportPath = Join-Path $pairDir 'cc-report.md'
  $script:promptPath = Join-Path $pairDir 'codex-prompt.md'
  $script:replyPath = Join-Path $pairDir 'codex-reply.md'
  $script:inboxPath = Join-Path $pairDir 'cc-inbox.md'
  $script:phase = ''
  $script:route = ''
  $script:nextAction = ''
  $startSnapshot = Get-WorkloopRunnerSnapshot

  $startText = @"
AI_WORKLOOP_RUNNER_STATUS=RUNNING
startedAt=$(Get-Date -Format o)
pair=$Pair
project=$ProjectRoot
phase=$($startSnapshot.phase)
route=$($startSnapshot.route)
nextAction=$($startSnapshot.nextAction)

Running ai-workloop.ps1. This runner only advances the Workloop state machine; it does not open Claude/Codex native TUI.

"@
  Set-Content -LiteralPath $script:outputPath -Value $startText -Encoding utf8
  Write-WorkloopRunnerStatus -Status 'running' -Message 'Running /workloop state machine.' -Phase ([string]$startSnapshot.phase) -Route ([string]$startSnapshot.route) -NextAction ([string]$startSnapshot.nextAction);
  Add-WorkloopRunnerLog -Event 'workloop-runner-start' -Detail "Running ai-workloop.ps1 for $Pair.";

  Write-Output "AI_WORKLOOP_RUNNER_PAIR=$Pair"
  Write-Output "AI_WORKLOOP_RUNNER_PROJECT=$ProjectRoot"
  Write-Output "AI_WORKLOOP_RUNNER_OUTPUT=$script:outputPath"
  Write-Output ''

  Invoke-WorkloopAutomaticLoop

  Add-WorkloopRunnerLog -Event 'workloop-runner-completed' -Detail "Output written to $script:outputPath.";
  $endSnapshot = Get-WorkloopRunnerSnapshot
  $endMessage = switch ([string]$endSnapshot.phase) {
    'codex_review' { 'Workloop completed; cc-report.md 仍等待 Codex 裁决或裁决结果未写入。' }
    'cc_followup' { 'Workloop completed; Codex 裁决已就绪，下一步让 Claude Code 执行。' }
    'cc_execute' { 'Workloop completed; Claude Code 有未读任务需要执行。' }
    'completed' { 'Workloop completed; goal 已完成。' }
    'needs_user' { 'Workloop completed; goal 已停止，需要人工判断。' }
    default { 'Workloop completed.' }
  }
  Write-WorkloopRunnerStatus -Status 'completed' -Message $endMessage -Phase ([string]$endSnapshot.phase) -Route ([string]$endSnapshot.route) -NextAction ([string]$endSnapshot.nextAction);
  Write-Output ''
  Write-Output 'AI_WORKLOOP_RUNNER_STATUS=COMPLETED'
  exit 0
} catch {
  $message = $_.Exception.Message
  try {
    if ($script:outputPath) {
      Add-Content -LiteralPath $script:outputPath -Value "ERROR: $message" -Encoding utf8
    }
    Write-WorkloopRunnerStatus -Status 'failed' -Message $message -ExitCode 1;
  } catch {
  }
  Write-Error $message
  exit 1
} finally {
  Pop-Location
}
