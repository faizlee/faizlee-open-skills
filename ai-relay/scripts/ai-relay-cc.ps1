param(
  [string]$Pair,
  [ValidateSet('auto','pull','report')][string]$Mode = 'auto'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

function Invoke-AiRelayPull {
  param([string]$PairDir, [string]$PairId)
  $inboxPath = Join-Path $PairDir 'cc-inbox.md'
  $readPath = Join-Path $PairDir 'cc-inbox.read.md'
  $content = Read-AiRelayTextFile $inboxPath
  if ([string]::IsNullOrWhiteSpace($content)) {
    Write-Output "AI_RELAY_STATUS=NO_INBOX"
    Write-Host "当前没有新的 Codex 指令。"
    return
  }
  Set-Content -LiteralPath $readPath -Value $content -Encoding utf8
  Add-AiRelayLog -PairDir $PairDir -Event 'cc-pull' -Detail "Claude Code pulled inbox for $PairId."
  [void](Copy-AiRelayText $content)
  Write-Output $content
}

function Test-AiRelayUnreadInbox {
  param([string]$PairDir)
  $inboxPath = Join-Path $PairDir 'cc-inbox.md'
  $readPath = Join-Path $PairDir 'cc-inbox.read.md'
  $inbox = Read-AiRelayTextFile $inboxPath
  if ([string]::IsNullOrWhiteSpace($inbox)) { return $false }
  if ((Test-Path -LiteralPath $readPath) -and (Test-Path -LiteralPath $inboxPath)) {
    if ((Get-Item -LiteralPath $readPath).LastWriteTime -ge (Get-Item -LiteralPath $inboxPath).LastWriteTime) {
      return $false
    }
  }
  $read = Read-AiRelayTextFile $readPath
  $normalizedInbox = ($inbox -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  $normalizedRead = ($read -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  return ($normalizedInbox -ne $normalizedRead)
}

function Test-AiRelayUnreadCodexReply {
  param([string]$PairDir)
  $replyPath = Join-Path $PairDir 'codex-reply.md'
  $readPath = Join-Path $PairDir 'codex-reply.read.md'
  $reply = Read-AiRelayTextFile $replyPath
  if ([string]::IsNullOrWhiteSpace($reply)) { return $false }
  if ((Test-Path -LiteralPath $readPath) -and (Test-Path -LiteralPath $replyPath)) {
    if ((Get-Item -LiteralPath $readPath).LastWriteTime -ge (Get-Item -LiteralPath $replyPath).LastWriteTime) {
      return $false
    }
  }
  $read = Read-AiRelayTextFile $readPath
  $normalizedReply = ($reply -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  $normalizedRead = ($read -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  if ($normalizedReply -eq $normalizedRead) { return $false }
  $reportPath = Join-Path $PairDir 'cc-report.md'
  if ((Test-Path -LiteralPath $reportPath) -and (Test-Path -LiteralPath $replyPath)) {
    return ((Get-Item -LiteralPath $replyPath).LastWriteTime -ge (Get-Item -LiteralPath $reportPath).LastWriteTime)
  }
  return $true
}

function Invoke-AiRelayReadCodexReply {
  param([string]$PairDir, [string]$PairId)
  $replyPath = Join-Path $PairDir 'codex-reply.md'
  $readPath = Join-Path $PairDir 'codex-reply.read.md'
  $reply = Read-AiRelayTextFile $replyPath
  if ([string]::IsNullOrWhiteSpace($reply)) {
    Write-Output "AI_RELAY_STATUS=NO_CODEX_REPLY"
    Write-Host "当前没有 Codex 裁决。"
    return
  }
  Set-Content -LiteralPath $readPath -Value $reply -Encoding utf8
  Add-AiRelayLog -PairDir $PairDir -Event 'cc-read-codex-reply' -Detail "Claude Code read Codex reply for $PairId."
  [void](Copy-AiRelayText $reply)
  Write-Output $reply
}

function Test-AiRelayWaitingForCodexReply {
  param([string]$PairDir)
  $reportPath = Join-Path $PairDir 'cc-report.md'
  $replyPath = Join-Path $PairDir 'codex-reply.md'
  $report = Read-AiRelayTextFile $reportPath
  if ([string]::IsNullOrWhiteSpace($report)) { return $false }
  if (-not (Test-Path -LiteralPath $reportPath)) { return $false }
  if (-not (Test-Path -LiteralPath $replyPath)) { return $true }
  return ((Get-Item -LiteralPath $reportPath).LastWriteTime -gt (Get-Item -LiteralPath $replyPath).LastWriteTime)
}

function Get-AiRelayReplyDecision {
  param([string]$Reply)
  if ($Reply -match '## 1\. 验收判断\s*[\r\n]+([^\r\n]+)') {
    return $Matches[1].Trim()
  }
  if ($Reply -match '不接受') { return '不接受' }
  if ($Reply -match '部分接受') { return '部分接受' }
  if ($Reply -match '接受|完成') { return '接受' }
  return '无法判断'
}

function Get-AiRelayNextInstruction {
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

function Test-AiRelayGoalDone {
  param([string]$Reply, [string]$Decision, [string]$NextInstruction)
  if ($Decision -match '^接受' -and ($Reply -match '本轮完成|完成|不需要返工|不需要继续|无需继续')) { return $true }
  if ([string]::IsNullOrWhiteSpace($NextInstruction) -and $Decision -match '^接受') { return $true }
  if ($NextInstruction -match '无|不需要|无需|停止|完成') { return $true }
  return $false
}

function Update-AiRelayGoalAfterReply {
  param(
    [string]$PairDir,
    [string]$PairId,
    [string]$Reply,
    [string]$HistoryId
  )
  $goalPath = Join-Path $PairDir 'goal.json'
  if (-not (Test-Path -LiteralPath $goalPath)) { return }

  $goal = Get-Content -LiteralPath $goalPath -Raw -Encoding utf8 | ConvertFrom-Json
  if (-not $goal) { return }
  if ($goal.status -notin @('running','started')) { return }

  $decision = Get-AiRelayReplyDecision $Reply
  $next = Get-AiRelayNextInstruction $Reply
  $round = 0
  if ($goal.round -ne $null) { $round = [int]$goal.round }
  $round++

  $maxRounds = 5
  if ($goal.maxRounds -ne $null) { $maxRounds = [int]$goal.maxRounds }

  $status = 'running'
  $stopReason = ''
  if (Test-AiRelayGoalDone -Reply $Reply -Decision $decision -NextInstruction $next) {
    $status = 'completed'
    $stopReason = 'Codex accepted/completed the goal.'
  } elseif ($round -ge $maxRounds) {
    $status = 'stopped'
    $stopReason = 'Max rounds reached.'
  } elseif ($Reply -match '冲突风险.*需要.*用户|人工裁决|需要用户') {
    $status = 'stopped'
    $stopReason = 'Codex requested user decision or reported conflict risk.'
  }
  $startedAt = [string]$goal.startedAt
  if ($goal.startedAt -is [datetime]) {
    $startedAt = $goal.startedAt.ToString('o')
  }

  $updated = [ordered]@{
    pairId = [string]$goal.pairId
    goal = [string]$goal.goal
    status = $status
    round = $round
    maxRounds = $maxRounds
    startedAt = $startedAt
    updatedAt = (Get-Date).ToString('o')
    stopReason = $stopReason
    lastDecision = $decision
    lastNextInstruction = $next
    lastHistoryId = $HistoryId
  }
  Write-AiRelayJson $updated $goalPath

  $goalDir = Join-Path $PairDir 'goal'
  New-Item -ItemType Directory -Force -Path $goalDir | Out-Null
  $summary = @"
# Agent Workloop Summary

- Pair: $PairId
- Status: $status
- Round: $round / $maxRounds
- Decision: $decision
- History: $HistoryId
- Stop reason: $stopReason

## Goal
$($updated.goal)

## Last Next Instruction
$next
"@
  Set-Content -LiteralPath (Join-Path $goalDir 'goal-summary-latest.md') -Value $summary -Encoding utf8
  Set-Content -LiteralPath (Join-Path $goalDir ("goal-summary-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".md")) -Value $summary -Encoding utf8
  Add-AiRelayLog -PairDir $PairDir -Event 'goal-update' -Detail "status=$status round=$round decision=$decision historyId=$HistoryId"
}

function Invoke-AiRelayReport {
  param([string]$ProjectRoot, [string]$PairDir, [string]$PairId)
  $pair = Read-AiRelayPairJson $PairDir
  if (-not $pair.codexSessionId) {
    throw "pair.json does not contain codexSessionId. Run ai-relay-bind-codex.ps1 first."
  }

  $contextPath = Join-Path $PairDir 'context.md'
  $inboxPath = Join-Path $PairDir 'cc-inbox.md'
  $reportPath = Join-Path $PairDir 'cc-report.md'
  $promptPath = Join-Path $PairDir 'codex-prompt.md'
  $replyPath = Join-Path $PairDir 'codex-reply.md'
  $historyRoot = Join-Path $PairDir 'history'

  $context = Read-AiRelayTextFile $contextPath
  $report = Read-AiRelayTextFile $reportPath
  if ([string]::IsNullOrWhiteSpace($report)) {
    throw "cc-report.md is empty. Write a compressed report first."
  }

  $prompt = @"
$context

---

$report

---

# 固定输出格式要求

请只按以下格式输出，不要要求 Claude Code 返回大段日志，不要索取完整项目代码。

## 1. 验收判断
接受 / 不接受 / 部分接受。

## 2. 关键理由
3-6 条。

## 3. 是否需要返工
需要 / 不需要。
如果需要，说明返工原因。

## 4. 给 Claude Code 的下一轮指令
写成可以直接交给 Claude Code 的任务指令。
必须边界清晰、最小化、不要大范围重构。

## 5. 与其他 pair 的冲突风险
判断当前任务是否可能和其他 pair 冲突。
如果无法判断，明确说无法判断。

## 6. 额度控制建议
说明下一轮是否需要继续问 Codex，还是 Claude Code 可直接执行后再汇报。
"@
  Set-Content -LiteralPath $promptPath -Value $prompt -Encoding utf8

  New-Item -ItemType Directory -Force -Path $historyRoot | Out-Null
  $existingIndexes = Get-ChildItem -LiteralPath $historyRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(\d{4})-' } |
    ForEach-Object { [int]$Matches[1] }
  $nextIndex = 1
  if ($existingIndexes) {
    $nextIndex = (($existingIndexes | Measure-Object -Maximum).Maximum + 1)
  }
  $historyId = ('{0:D4}-{1}' -f [int]$nextIndex, (Get-Date -Format 'yyyyMMdd-HHmmss'))
  $historyDir = Join-Path $historyRoot $historyId
  New-Item -ItemType Directory -Force -Path $historyDir | Out-Null
  if (Test-Path -LiteralPath $inboxPath) {
    Copy-Item -LiteralPath $inboxPath -Destination (Join-Path $historyDir 'cc-inbox.md') -Force
  }
  Copy-Item -LiteralPath $reportPath -Destination (Join-Path $historyDir 'cc-report.md') -Force
  Copy-Item -LiteralPath $promptPath -Destination (Join-Path $historyDir 'codex-prompt.md') -Force

  $summary = [ordered]@{
    pairId = $PairId
    historyId = $historyId
    createdAt = (Get-Date).ToString('o')
    projectRoot = $ProjectRoot
    codexSessionId = [string]$pair.codexSessionId
    status = 'prompt-created'
    inboxBytes = if (Test-Path -LiteralPath $inboxPath) { (Get-Item -LiteralPath $inboxPath).Length } else { 0 }
    reportBytes = (Get-Item -LiteralPath $reportPath).Length
    promptBytes = (Get-Item -LiteralPath $promptPath).Length
    replyBytes = 0
  }
  Write-AiRelayJson $summary (Join-Path $historyDir 'summary.json')

  if (Get-Command codex -ErrorAction SilentlyContinue) {
    $codexSessionId = [string]$pair.codexSessionId
    $args = @('exec', '-C', $ProjectRoot, 'resume', '--ignore-user-config', '-c', 'sandbox_mode="read-only"', '-o', $replyPath, $codexSessionId, '-')
    Add-AiRelayLog -PairDir $PairDir -Event 'cc-report-to-codex' -Detail "historyId: $historyId`nRunning: codex exec -C <projectRoot> resume --ignore-user-config -c sandbox_mode=<read-only> -o <codex-reply.md> <codexSessionId> -"
    $oldErrorActionPreference = $ErrorActionPreference
    $oldNativePreference = $null
    $hadNativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
    if ($hadNativePreference) { $oldNativePreference = $PSNativeCommandUseErrorActionPreference }
    try {
      $ErrorActionPreference = 'Continue'
      if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $false }
      $codexCliOutput = Get-Content -LiteralPath $promptPath -Raw -Encoding utf8 | & codex @args 2>&1 | Out-String
    } finally {
      $ErrorActionPreference = $oldErrorActionPreference
      if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $oldNativePreference }
    }
    Set-Content -LiteralPath (Join-Path $historyDir 'codex-cli-output.log') -Value $codexCliOutput -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
      $summary.status = "codex-failed-$LASTEXITCODE"
      Write-AiRelayJson $summary (Join-Path $historyDir 'summary.json')
      throw "codex exec resume failed with exit code $LASTEXITCODE.`n$codexCliOutput"
    }
  } else {
    throw "codex CLI not found in PATH."
  }

  $reply = Read-AiRelayTextFile $replyPath
  if (Test-Path -LiteralPath $replyPath) {
    Copy-Item -LiteralPath $replyPath -Destination (Join-Path $historyDir 'codex-reply.md') -Force
    $summary.replyBytes = (Get-Item -LiteralPath $replyPath).Length
  }
  $summary.status = 'completed'
  Write-AiRelayJson $summary (Join-Path $historyDir 'summary.json')
  Update-AiRelayGoalAfterReply -PairDir $PairDir -PairId $PairId -Reply $reply -HistoryId $historyId
  Add-AiRelayLog -PairDir $PairDir -Event 'codex-reply' -Detail "historyId: $historyId`nCodex reply written to codex-reply.md and archived."
  [void](Copy-AiRelayText $reply)
  Write-Host "History saved: $historyDir"
  Write-Output $reply
}

$projectRoot = Get-AiRelayProjectRoot
$pairId = Get-AiRelayPairId -ProjectRoot $projectRoot -Pair $Pair
Assert-AiRelayPairName $pairId
$pairDir = Get-AiRelayPairDir $projectRoot $pairId
if (-not (Test-Path -LiteralPath $pairDir)) {
  throw "Pair not found: $pairDir"
}

switch ($Mode) {
  'pull' { Invoke-AiRelayPull -PairDir $pairDir -PairId $pairId }
  'report' { Invoke-AiRelayReport -ProjectRoot $projectRoot -PairDir $pairDir -PairId $pairId }
  'auto' {
    if (Test-AiRelayUnreadCodexReply -PairDir $pairDir) {
      Write-Output "AI_RELAY_STATUS=CODEX_REPLY_UNREAD"
      Invoke-AiRelayReadCodexReply -PairDir $pairDir -PairId $pairId
    } elseif (Test-AiRelayUnreadInbox -PairDir $pairDir) {
      Write-Output "AI_RELAY_STATUS=CC_INBOX_UNREAD"
      Invoke-AiRelayPull -PairDir $pairDir -PairId $pairId
    } elseif (Test-AiRelayWaitingForCodexReply -PairDir $pairDir) {
      Write-Output "AI_RELAY_STATUS=WAITING_FOR_CODEX"
      Write-Output "AI_RELAY_ACTION=RUN_REPORT"
      Write-Host "cc-report.md 比 codex-reply.md 新。请执行 ai-workloop.ps1 $pairId 或 ai-relay-cc.ps1 -Pair $pairId -Mode report 送审。不要提示用户去 Codex 执行 /relay。"
    } else {
      Write-Output "AI_RELAY_STATUS=IDLE"
      Write-Output "AI_RELAY_ACTION=NO_NEW_MESSAGE"
      Write-Host "当前没有新的 Codex 指令或未读裁决。只有在你完成了新的本轮任务后，才需要写 cc-report.md 并执行 ai-relay-cc.ps1 -Pair $pairId -Mode report。"
    }
  }
}
