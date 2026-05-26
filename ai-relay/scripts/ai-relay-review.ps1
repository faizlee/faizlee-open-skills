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
  Encode-AiRelayHtml $Text
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
  $files = Get-Matches $allText '([A-Za-z0-9_\-./\\\[\]]+\.(tsx|jsx|json|yaml|yml|ps1|txt|md|ts|js))'
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
  function New-ReviewListHtml {
    param($Items, [string]$EmptyText)
    if (-not $Items -or @($Items).Count -eq 0) { return "<p class=""muted"">$(Encode-Html $EmptyText)</p>" }
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('<ul class="list">')
    foreach ($item in $Items) { [void]$builder.AppendLine("<li>$(Encode-Html ([string]$item))</li>") }
    [void]$builder.AppendLine('</ul>')
    return $builder.ToString()
  }

  $signalsHtml = New-ReviewListHtml -Items $signals -EmptyText '未发现明显低效循环信号。'
  $hotFilesHtml = [System.Text.StringBuilder]::new()
  if ($hotFiles) {
    [void]$hotFilesHtml.AppendLine('<ul class="list hot-list">')
    foreach ($item in $hotFiles) {
      $fileUri = ConvertTo-AiRelayFileUri -ProjectRoot $projectRoot -Path ([string]$item.Key)
      $filePart = if ($fileUri) {
        "<a href=""$(Encode-Html $fileUri)""><code>$(Encode-Html ([string]$item.Key))</code></a><small>可打开本地文件</small>"
      } else {
        "<code>$(Encode-Html ([string]$item.Key))</code><small>未在当前项目中找到可打开路径</small>"
      }
      [void]$hotFilesHtml.AppendLine("<li><span>$filePart</span><strong>$(Encode-Html ([string]$item.Value)) 次</strong></li>")
    }
    [void]$hotFilesHtml.AppendLine('</ul>')
  } else {
    [void]$hotFilesHtml.AppendLine('<p class="muted">未发现文件路径。</p>')
  }
  $hotErrorsHtml = [System.Text.StringBuilder]::new()
  if ($hotErrors) {
    [void]$hotErrorsHtml.AppendLine('<ul class="list hot-list">')
    foreach ($item in $hotErrors) {
      [void]$hotErrorsHtml.AppendLine("<li><code>$(Encode-Html ([string]$item.Key))</code><strong>$(Encode-Html ([string]$item.Value)) 次</strong></li>")
    }
    [void]$hotErrorsHtml.AppendLine('</ul>')
  } else {
    [void]$hotErrorsHtml.AppendLine('<p class="muted">未发现明显问题关键词。</p>')
  }
  $hotCommandsHtml = [System.Text.StringBuilder]::new()
  if ($hotCommands) {
    [void]$hotCommandsHtml.AppendLine('<ul class="list hot-list">')
    foreach ($item in $hotCommands) {
      [void]$hotCommandsHtml.AppendLine("<li><code>$(Encode-Html ([string]$item.Key))</code><strong>$(Encode-Html ([string]$item.Value)) 次</strong></li>")
    }
    [void]$hotCommandsHtml.AppendLine('</ul>')
  } else {
    [void]$hotCommandsHtml.AppendLine('<p class="muted">未发现明确命令。</p>')
  }
  $timelineHtml = [System.Text.StringBuilder]::new()
  foreach ($round in $rounds) {
    $tone = if ($round.decision -eq '不接受' -or $round.needsRework) { 'bad' } elseif ($round.decision -eq '部分接受' -or -not $round.hasVerification) { 'warn' } else { 'good' }
    [void]$timelineHtml.AppendLine("<article class=""round $tone"">")
    [void]$timelineHtml.AppendLine("<div class=""round-head""><strong>$(Encode-Html $round.id)</strong><span>$(Encode-Html $round.decision)</span></div>")
    [void]$timelineHtml.AppendLine("<dl>")
    [void]$timelineHtml.AppendLine("<dt>时间</dt><dd>$(Encode-Html $round.createdAt)</dd>")
    [void]$timelineHtml.AppendLine("<dt>返工</dt><dd>$(Encode-Html ([string]$round.needsRework))</dd>")
    [void]$timelineHtml.AppendLine("<dt>验证</dt><dd>$(Encode-Html ([string]$round.hasVerification))</dd>")
    [void]$timelineHtml.AppendLine("<dt>乱码</dt><dd>$(Encode-Html ([string]$round.hasMojibake))</dd>")
    [void]$timelineHtml.AppendLine("</dl>")
    [void]$timelineHtml.AppendLine("<details><summary>查看摘要</summary><h4>Codex 指令</h4><pre>$(Encode-Html $round.inboxSummary)</pre><h4>CC 汇报</h4><pre>$(Encode-Html $round.reportSummary)</pre><h4>Codex 回复</h4><pre>$(Encode-Html $round.replySummary)</pre></details>")
    [void]$timelineHtml.AppendLine('</article>')
  }
  $html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>Agent Workloop 工作复盘报告 - $pairId</title>
  <style>
    body { font-family: "Segoe UI", "Microsoft YaHei", Arial, sans-serif; margin: 0; background: #f4f2ed; color: #1f2328; line-height: 1.55; }
    main { max-width: 1180px; margin: 0 auto; min-height: 100vh; padding: 32px 28px 56px; }
    h1 { margin: 0 0 8px; }
    h2 { margin: 0 0 14px; font-size: 20px; }
    section { background:#fff; border:1px solid #d8ddd8; border-radius:8px; padding:18px; margin:16px 0; }
    pre, blockquote { background: #f6f8fa; border: 1px solid #d0d7de; border-radius: 6px; padding: 12px 14px; white-space: pre-wrap; word-break: break-word; }
    code { background: #f6f8fa; padding: 2px 5px; border-radius: 4px; }
    .meta, .muted { color:#65717d; }
    .metrics { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; }
    .metric { border:1px solid #d8ddd8; border-radius:8px; padding:12px; background:#fbfcfa; }
    .metric strong { display:block; font-size:24px; }
    .metric span { color:#65717d; font-size:13px; }
    .list { margin:0; padding-left:20px; }
    .hot-list { list-style:none; padding:0; display:grid; gap:8px; }
    .hot-list li { display:flex; justify-content:space-between; gap:14px; border-bottom:1px solid #edf0eb; padding-bottom:8px; }
    .hot-list small { display:block; color:#65717d; }
    .two-col { display:grid; grid-template-columns:1fr 1fr; gap:16px; }
    .round { border-left:4px solid #8a927f; border-radius:8px; padding:12px; background:#fbfcfa; margin:10px 0; }
    .round.good { border-left-color:#176b5d; }
    .round.warn { border-left-color:#d08a2f; }
    .round.bad { border-left-color:#b76a6a; }
    .round-head { display:flex; justify-content:space-between; gap:10px; }
    .round dl { display:grid; grid-template-columns:80px 1fr; gap:6px 10px; }
    .round dt { color:#65717d; }
    .round dd { margin:0; }
    @media (max-width: 900px) { .two-col { grid-template-columns:1fr; } }
  </style>
</head>
<body>
<main>
  <header>
    <h1>Agent Workloop 工作复盘报告</h1>
    <p class="meta">Pair <code>$(Encode-Html $pairId)</code> · 项目 <code>$(Encode-Html $projectRoot)</code> · 分析轮数 $totalRounds</p>
  </header>
  <section>
    <h2>总览</h2>
    <div class="metrics">
      <div class="metric"><strong>$partialOrRejected</strong><span>部分接受 / 不接受</span></div>
      <div class="metric"><strong>$reworkCount</strong><span>返工轮数</span></div>
      <div class="metric"><strong>$mojibakeCount</strong><span>乱码轮数</span></div>
      <div class="metric"><strong>$missingVerificationCount</strong><span>缺少验证</span></div>
    </div>
    <p><strong>建议：</strong>$(Encode-Html $recommendation)</p>
  </section>
  <section>
    <h2>低效循环信号</h2>
    $signalsHtml
  </section>
  <section>
    <h2>时间线</h2>
    $($timelineHtml.ToString())
  </section>
  <section class="two-col">
    <div>
      <h2>文件热点</h2>
      $($hotFilesHtml.ToString())
    </div>
    <div>
      <h2>问题热点</h2>
      $($hotErrorsHtml.ToString())
    </div>
  </section>
  <section>
    <h2>命令 / 验证线索</h2>
    $($hotCommandsHtml.ToString())
  </section>
  <section>
    <details>
      <summary>查看原始 Markdown</summary>
      <pre>$(Encode-Html $mdText)</pre>
    </details>
  </section>
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
