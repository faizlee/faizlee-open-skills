param(
  [string]$Pair,
  [int]$Last = 0,
  [ValidateSet('md','html','both')][string]$Format = 'both',
  [string]$OutDir,
  [switch]$Open
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

function Read-RelayFile {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    return (Get-Content -LiteralPath $Path -Raw -Encoding utf8)
  }
  return ''
}

function Encode-Html {
  param([string]$Text)
  [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-Decision {
  param([string]$Reply)
  if ($Reply -match '不接受') { return '不接受' }
  if ($Reply -match '部分接受') { return '部分接受' }
  if ($Reply -match '接受') { return '接受' }
  return '无法判断'
}

function Get-NeedsRework {
  param([string]$Reply)
  if ($Reply -match '不需要继续返工|不需要返工|不需要') { return $false }
  if ($Reply -match '需要返工|是否需要返工[\s\S]{0,80}需要|返工原因') { return $true }
  return $false
}

function Get-TextSummary {
  param([string]$Text, [int]$MaxLength = 260)
  $clean = ($Text -replace '\r', '' -replace '\n{2,}', "`n").Trim()
  if ($clean.Length -le $MaxLength) { return $clean }
  return $clean.Substring(0, $MaxLength) + '...'
}

function Get-Matches {
  param([string]$Text, [string]$Pattern)
  [regex]::Matches($Text, $Pattern) | ForEach-Object { $_.Value } | Sort-Object -Unique
}

$projectRoot = Get-AiRelayProjectRoot
$pairId = Get-AiRelayPairId -ProjectRoot $projectRoot -Pair $Pair
Assert-AiRelayPairName $pairId
$pairDir = Get-AiRelayPairDir $projectRoot $pairId
$historyRoot = Join-Path $pairDir 'history'
if (-not (Test-Path -LiteralPath $historyRoot)) {
  throw "No history found for pair '$pairId': $historyRoot"
}

$roundDirs = Get-ChildItem -LiteralPath $historyRoot -Directory | Sort-Object Name
if ($Last -gt 0 -and $roundDirs.Count -gt $Last) {
  $roundDirs = $roundDirs | Select-Object -Last $Last
}
if (-not $roundDirs) {
  throw "No history rounds found for pair '$pairId'."
}

if (-not $OutDir) {
  $OutDir = Join-Path $pairDir 'reviews'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$rounds = @()
$fileCounts = @{}
$errorCounts = @{}
$commandCounts = @{}
$reworkReasons = New-Object System.Collections.Generic.List[string]

foreach ($dir in $roundDirs) {
  $summaryPath = Join-Path $dir.FullName 'summary.json'
  $summary = $null
  if (Test-Path -LiteralPath $summaryPath) {
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding utf8 | ConvertFrom-Json
  }

  $inbox = Read-RelayFile (Join-Path $dir.FullName 'cc-inbox.md')
  $report = Read-RelayFile (Join-Path $dir.FullName 'cc-report.md')
  $reply = Read-RelayFile (Join-Path $dir.FullName 'codex-reply.md')
  $allText = "$inbox`n$report`n$reply"

  $decision = Get-Decision $reply
  $needsRework = Get-NeedsRework $reply
  $hasMojibake = ($allText -match '\?\?\?')
  $hasVerification = ($report -match '验证|verification|test|pnpm|passed|failed|typecheck')
  $files = Get-Matches $allText '([A-Za-z0-9_\-./\\\[\]]+\.(tsx|ts|js|jsx|json|md|ps1|txt))'
  $errors = Get-Matches $allText '(TypeError|ReferenceError|SyntaxError|failed|失败|错误|乱码|补证据|证据不足|返工|不接受|部分接受)'
  $commands = Get-Matches $allText '(pnpm\s+[A-Za-z0-9:_\-]+|npm\s+[A-Za-z0-9:_\-]+|git\s+[A-Za-z0-9:_\-]+|ai-relay-[A-Za-z0-9:_\-]+\.ps1)'

  foreach ($file in $files) {
    if (-not $fileCounts.ContainsKey($file)) { $fileCounts[$file] = 0 }
    $fileCounts[$file]++
  }
  foreach ($err in $errors) {
    if (-not $errorCounts.ContainsKey($err)) { $errorCounts[$err] = 0 }
    $errorCounts[$err]++
  }
  foreach ($cmd in $commands) {
    if (-not $commandCounts.ContainsKey($cmd)) { $commandCounts[$cmd] = 0 }
    $commandCounts[$cmd]++
  }
  if ($needsRework) {
    if ($reply -match '返工原因[:：]?\s*(.+)') {
      $reworkReasons.Add($Matches[1].Trim())
    } elseif ($reply -match '证据不足|补证据') {
      $reworkReasons.Add('证据不足或需要补证据')
    } elseif ($reply -match '乱码') {
      $reworkReasons.Add('报告乱码影响审计')
    } else {
      $reworkReasons.Add('Codex 要求返工')
    }
  }

  $rounds += [pscustomobject]@{
    id = $dir.Name
    createdAt = if ($summary) { [string]$summary.createdAt } else { '' }
    status = if ($summary) { [string]$summary.status } else { '' }
    codexSessionId = if ($summary) { [string]$summary.codexSessionId } else { '' }
    decision = $decision
    needsRework = $needsRework
    hasMojibake = $hasMojibake
    hasVerification = $hasVerification
    fileCount = @($files).Count
    errorCount = @($errors).Count
    commandCount = @($commands).Count
    inboxSummary = Get-TextSummary $inbox
    reportSummary = Get-TextSummary $report
    replySummary = Get-TextSummary $reply
    path = $dir.FullName
  }
}

$totalRounds = @($rounds).Count
$partialOrRejected = @($rounds | Where-Object { $_.decision -in @('部分接受','不接受') }).Count
$reworkCount = @($rounds | Where-Object { $_.needsRework }).Count
$mojibakeCount = @($rounds | Where-Object { $_.hasMojibake }).Count
$missingVerificationCount = @($rounds | Where-Object { -not $_.hasVerification }).Count
$consecutiveWeak = 0
foreach ($round in ($rounds | Sort-Object id -Descending)) {
  if ($round.decision -in @('部分接受','不接受')) { $consecutiveWeak++ } else { break }
}

$signals = New-Object System.Collections.Generic.List[string]
if ($consecutiveWeak -ge 3) { $signals.Add("连续 $consecutiveWeak 轮部分接受/不接受，可能进入低效循环。") }
if ($reworkCount -ge 2) { $signals.Add("累计 $reworkCount 轮需要返工，建议暂停继续修复并复盘原因。") }
if ($mojibakeCount -gt 0) { $signals.Add("发现 $mojibakeCount 轮报告或上下文包含 ???，存在编码/审计质量问题。") }
if ($missingVerificationCount -gt 0) { $signals.Add("发现 $missingVerificationCount 轮没有明确验证信息。") }

$hotFiles = $fileCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
foreach ($item in $hotFiles | Where-Object { $_.Value -ge 3 }) {
  $signals.Add("文件热点：$($item.Key) 在 $($item.Value) 轮/处被反复提到。")
}
$hotErrors = $errorCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
foreach ($item in $hotErrors | Where-Object { $_.Value -ge 3 }) {
  $signals.Add("问题热点：$($item.Key) 出现 $($item.Value) 次。")
}
if ($signals.Count -eq 0) {
  $signals.Add('未发现明显低效循环信号。')
}

$recommendation = '继续推进'
if ($consecutiveWeak -ge 3 -or $reworkCount -ge 3) {
  $recommendation = '建议暂停继续修复，先做人工复盘'
} elseif ($mojibakeCount -gt 0 -or $missingVerificationCount -gt 0) {
  $recommendation = '建议先修复报告质量或补齐验证信息'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$mdPath = Join-Path $OutDir "ai-relay-review-$pairId-$stamp.md"
$htmlPath = Join-Path $OutDir "ai-relay-review-$pairId-$stamp.html"

$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine("# Agent Workloop 工作复盘报告")
[void]$md.AppendLine("")
[void]$md.AppendLine('- Pair: `' + $pairId + '`')
[void]$md.AppendLine('- 项目目录: `' + $projectRoot + '`')
[void]$md.AppendLine("- 复盘时间: $(Get-Date -Format o)")
[void]$md.AppendLine("- 分析轮数: $totalRounds")
[void]$md.AppendLine("")
[void]$md.AppendLine("## 1. 总览")
[void]$md.AppendLine("")
[void]$md.AppendLine("- 部分接受/不接受轮数: $partialOrRejected")
[void]$md.AppendLine("- 返工轮数: $reworkCount")
[void]$md.AppendLine("- 乱码轮数: $mojibakeCount")
[void]$md.AppendLine("- 缺少验证信息轮数: $missingVerificationCount")
[void]$md.AppendLine("- 建议: **$recommendation**")
[void]$md.AppendLine("")
[void]$md.AppendLine("## 2. 低效循环信号")
[void]$md.AppendLine("")
foreach ($signal in $signals) { [void]$md.AppendLine("- $signal") }
[void]$md.AppendLine("")
[void]$md.AppendLine("## 3. 时间线")
foreach ($round in $rounds) {
  [void]$md.AppendLine("")
  [void]$md.AppendLine("### $($round.id)")
  [void]$md.AppendLine("")
  [void]$md.AppendLine("- 时间: $($round.createdAt)")
  [void]$md.AppendLine("- 状态: $($round.status)")
  [void]$md.AppendLine("- Codex 判断: $($round.decision)")
  [void]$md.AppendLine("- 是否返工: $($round.needsRework)")
  [void]$md.AppendLine("- 是否包含乱码: $($round.hasMojibake)")
  [void]$md.AppendLine("- 是否有验证信息: $($round.hasVerification)")
  [void]$md.AppendLine('- 历史目录: `' + $round.path + '`')
  [void]$md.AppendLine("")
  [void]$md.AppendLine("Codex 指令摘要：")
  [void]$md.AppendLine("")
  [void]$md.AppendLine("> $($round.inboxSummary -replace "`n", "`n> ")")
  [void]$md.AppendLine("")
  [void]$md.AppendLine("CC 汇报摘要：")
  [void]$md.AppendLine("")
  [void]$md.AppendLine("> $($round.reportSummary -replace "`n", "`n> ")")
  [void]$md.AppendLine("")
  [void]$md.AppendLine("Codex 回复摘要：")
  [void]$md.AppendLine("")
  [void]$md.AppendLine("> $($round.replySummary -replace "`n", "`n> ")")
}

[void]$md.AppendLine("")
[void]$md.AppendLine("## 4. 返工原因")
[void]$md.AppendLine("")
if ($reworkReasons.Count -eq 0) {
  [void]$md.AppendLine("- 未发现明确返工原因。")
} else {
  foreach ($reason in $reworkReasons) { [void]$md.AppendLine("- $reason") }
}

[void]$md.AppendLine("")
[void]$md.AppendLine("## 5. 文件热点")
[void]$md.AppendLine("")
if ($hotFiles) {
  foreach ($item in $hotFiles) { [void]$md.AppendLine('- `' + $item.Key + '`: ' + $item.Value) }
} else {
  [void]$md.AppendLine("- 未发现文件路径。")
}

[void]$md.AppendLine("")
[void]$md.AppendLine("## 6. 问题热点")
[void]$md.AppendLine("")
if ($hotErrors) {
  foreach ($item in $hotErrors) { [void]$md.AppendLine('- `' + $item.Key + '`: ' + $item.Value) }
} else {
  [void]$md.AppendLine("- 未发现明显问题关键词。")
}

[void]$md.AppendLine("")
[void]$md.AppendLine("## 7. 命令/验证线索")
[void]$md.AppendLine("")
$hotCommands = $commandCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
if ($hotCommands) {
  foreach ($item in $hotCommands) { [void]$md.AppendLine('- `' + $item.Key + '`: ' + $item.Value) }
} else {
  [void]$md.AppendLine("- 未发现明确命令。")
}

[void]$md.AppendLine("")
[void]$md.AppendLine("## 8. 下一步建议")
[void]$md.AppendLine("")
[void]$md.AppendLine("- $recommendation")
[void]$md.AppendLine("- 如果继续推进，请给 Claude Code 一条边界清晰、只包含一个目标的最小指令。")
[void]$md.AppendLine("- 如果出现连续返工，请先让 CC 基于本报告写人工复盘，不要继续扩大修复范围。")

$mdText = $md.ToString()
if ($Format -eq 'md' -or $Format -eq 'both') {
  $encoding = [System.Text.UTF8Encoding]::new($true)
  [System.IO.File]::WriteAllText($mdPath, $mdText, $encoding)
}
if ($Format -eq 'html' -or $Format -eq 'both') {
  $html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>Agent Workloop 工作复盘报告 - $pairId</title>
  <style>
    body { font-family: "Segoe UI", "Microsoft YaHei", Arial, sans-serif; margin: 0; background: #f6f8fa; color: #1f2328; line-height: 1.55; }
    main { max-width: 1120px; margin: 0 auto; min-height: 100vh; background: white; padding: 32px 28px 56px; }
    h1 { margin: 0 0 8px; }
    h2 { border-top: 1px solid #d0d7de; padding-top: 22px; margin-top: 30px; }
    pre, blockquote { background: #f6f8fa; border: 1px solid #d0d7de; border-radius: 6px; padding: 12px 14px; white-space: pre-wrap; word-break: break-word; }
    code { background: #f6f8fa; padding: 2px 5px; border-radius: 4px; }
    .summary { background: #ddf4ff; border: 1px solid #54aeef; border-radius: 6px; padding: 12px 14px; }
  </style>
</head>
<body>
<main>
<pre>$(Encode-Html $mdText)</pre>
</main>
</body>
</html>
"@
  $encoding = [System.Text.UTF8Encoding]::new($true)
  [System.IO.File]::WriteAllText($htmlPath, $html, $encoding)
}

Write-Host "Agent Workloop review generated:"
if ($Format -eq 'md' -or $Format -eq 'both') { Write-Host "Markdown: $mdPath" }
if ($Format -eq 'html' -or $Format -eq 'both') { Write-Host "HTML: $htmlPath" }
if ($Open) {
  if ($Format -eq 'md') { Invoke-Item -LiteralPath $mdPath } else { Invoke-Item -LiteralPath $htmlPath }
}
