param(
  [string]$Pair,
  [ValidateSet('auto','pull','report')][string]$Mode = 'auto'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

function Invoke-AiRelayPull {
  param([string]$PairDir, [string]$PairId)
  $inboxPath = Join-Path $PairDir 'cc-inbox.md'
  $readPath = Join-Path $PairDir 'cc-inbox.read.md'
  $content = Read-AiRelayTextFile $inboxPath
  if ([string]::IsNullOrWhiteSpace($content)) {
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
  $read = Read-AiRelayTextFile $readPath
  return ($inbox.Trim() -ne $read.Trim())
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
  $historyId = ('{0:D4}-{1}' -f $nextIndex, (Get-Date -Format 'yyyyMMdd-HHmmss'))
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
    $args = @('exec', '-C', $ProjectRoot, '--sandbox', 'read-only', 'resume', $codexSessionId, '-', '--output-last-message', $replyPath)
    Add-AiRelayLog -PairDir $PairDir -Event 'cc-report-to-codex' -Detail "historyId: $historyId`nRunning: codex exec -C <projectRoot> --sandbox read-only resume <codexSessionId> - --output-last-message <codex-reply.md>"
    Get-Content -LiteralPath $promptPath -Raw -Encoding utf8 | & codex @args
    if ($LASTEXITCODE -ne 0) {
      $summary.status = "codex-failed-$LASTEXITCODE"
      Write-AiRelayJson $summary (Join-Path $historyDir 'summary.json')
      throw "codex exec resume failed with exit code $LASTEXITCODE."
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
    if (Test-AiRelayUnreadInbox -PairDir $pairDir) {
      Invoke-AiRelayPull -PairDir $pairDir -PairId $pairId
    } else {
      Write-Host "当前没有新的 Codex 指令。请先把本轮压缩报告写入 cc-report.md，然后执行 report。"
    }
  }
}
