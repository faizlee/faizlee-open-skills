param(
  [string[]]$ProjectRoot,
  [string]$OutDir,
  [switch]$Open
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

function Encode-WorkloopHtml {
  param([string]$Text)
  [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Read-WorkloopJson {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    try {
      return (Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json)
    } catch {
      return $null
    }
  }
  return $null
}

function Get-WorkloopFileTime {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    return (Get-Item -LiteralPath $Path).LastWriteTime
  }
  return $null
}

function Read-WorkloopText {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    return (Get-Content -LiteralPath $Path -Raw -Encoding utf8)
  }
  return ''
}

function Test-WorkloopUnread {
  param([string]$SourcePath, [string]$ReadPath)
  $source = Read-WorkloopText $SourcePath
  if ([string]::IsNullOrWhiteSpace($source)) { return $false }
  $sourceTime = Get-WorkloopFileTime $SourcePath
  $readTime = Get-WorkloopFileTime $ReadPath
  if ($sourceTime -and $readTime -and $readTime -ge $sourceTime) { return $false }
  $read = Read-WorkloopText $ReadPath
  $normalizedSource = ($source -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  $normalizedRead = ($read -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  return ($normalizedSource -ne $normalizedRead)
}

function Get-WorkloopExcerpt {
  param([string]$Path, [int]$MaxChars = 220)
  $text = (Read-WorkloopText $Path).Trim()
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }
  $text = $text -replace "`r`n", "`n"
  if ($text.Length -gt $MaxChars) {
    return $text.Substring(0, $MaxChars) + '...'
  }
  return $text
}

function Get-WorkloopDecision {
  param([string]$Reply)
  if ($Reply -match '## 1\. 验收判断\s*[\r\n]+([^\r\n]+)') {
    return $Matches[1].Trim()
  }
  if ($Reply -match '不接受') { return '不接受' }
  if ($Reply -match '部分接受') { return '部分接受' }
  if ($Reply -match '接受|完成') { return '接受' }
  return ''
}

function Get-WorkloopPairRow {
  param([string]$ProjectRoot, [string]$PairDir)

  $pairId = Split-Path -Leaf $PairDir
  $pairJson = Read-WorkloopJson (Join-Path $PairDir 'pair.json')
  $goalJson = Read-WorkloopJson (Join-Path $PairDir 'goal.json')
  $inboxPath = Join-Path $PairDir 'cc-inbox.md'
  $inboxReadPath = Join-Path $PairDir 'cc-inbox.read.md'
  $reportPath = Join-Path $PairDir 'cc-report.md'
  $replyPath = Join-Path $PairDir 'codex-reply.md'
  $replyReadPath = Join-Path $PairDir 'codex-reply.read.md'
  $historyRoot = Join-Path $PairDir 'history'

  $unreadReply = Test-WorkloopUnread -SourcePath $replyPath -ReadPath $replyReadPath
  $unreadInbox = Test-WorkloopUnread -SourcePath $inboxPath -ReadPath $inboxReadPath
  $report = Read-WorkloopText $reportPath
  $hasReport = -not [string]::IsNullOrWhiteSpace($report)
  $reportTime = Get-WorkloopFileTime $reportPath
  $replyTime = Get-WorkloopFileTime $replyPath
  $reportReady = $hasReport -and $reportTime -and ((-not $replyTime) -or ($reportTime -gt $replyTime))

  $status = '空闲'
  $statusClass = 'idle'
  if ($unreadReply) {
    $status = '有未读 Codex 裁决'
    $statusClass = 'reply'
  } elseif ($reportReady) {
    $status = '报告待送审'
    $statusClass = 'report'
  } elseif ($unreadInbox) {
    $status = '有未读任务'
    $statusClass = 'inbox'
  } elseif ($goalJson -and $goalJson.status) {
    $status = "Workloop: $($goalJson.status)"
    $statusClass = [string]$goalJson.status
  }

  $historyCount = 0
  if (Test-Path -LiteralPath $historyRoot) {
    $historyCount = @(Get-ChildItem -LiteralPath $historyRoot -Directory -ErrorAction SilentlyContinue).Count
  }

  $reply = Read-WorkloopText $replyPath
  $lastTime = @($reportTime, $replyTime, (Get-WorkloopFileTime $inboxPath)) |
    Where-Object { $_ } |
    Sort-Object -Descending |
    Select-Object -First 1

  [pscustomobject]@{
    ProjectRoot = $ProjectRoot
    ProjectName = Split-Path -Leaf $ProjectRoot
    PairId = $pairId
    Task = if ($pairJson) { [string]$pairJson.task } else { '' }
    Role = if ($pairJson) { [string]$pairJson.role } else { '' }
    CodexSessionId = if ($pairJson) { [string]$pairJson.codexSessionId } else { '' }
    Goal = if ($goalJson) { [string]$goalJson.goal } else { '' }
    GoalStatus = if ($goalJson) { [string]$goalJson.status } else { '' }
    Round = if ($goalJson -and $goalJson.round -ne $null) { [string]$goalJson.round } else { '' }
    MaxRounds = if ($goalJson -and $goalJson.maxRounds -ne $null) { [string]$goalJson.maxRounds } else { '' }
    LastDecision = if ($goalJson -and $goalJson.lastDecision) { [string]$goalJson.lastDecision } else { Get-WorkloopDecision $reply }
    Status = $status
    StatusClass = $statusClass
    LastUpdated = if ($lastTime) { $lastTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
    HistoryCount = $historyCount
    PairDir = $PairDir
    InboxExcerpt = Get-WorkloopExcerpt $inboxPath
    ReportExcerpt = Get-WorkloopExcerpt $reportPath
    ReplyExcerpt = Get-WorkloopExcerpt $replyPath
  }
}

if (-not $ProjectRoot -or $ProjectRoot.Count -eq 0) {
  $ProjectRoot = @((Get-AiRelayProjectRoot))
}

$projectInputs = @()
foreach ($root in $ProjectRoot) {
  if ([string]::IsNullOrWhiteSpace($root)) { continue }
  $projectInputs += ([string]$root -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") })
}

$resolvedProjects = @()
foreach ($root in $projectInputs) {
  if ([string]::IsNullOrWhiteSpace($root)) { continue }
  $resolved = (Resolve-Path -LiteralPath $root -ErrorAction SilentlyContinue)
  if ($resolved) {
    $resolvedProjects += $resolved.ProviderPath
  } else {
    Write-Warning "Project root not found: $root"
  }
}

if (-not $OutDir) {
  $OutDir = Join-Path $HOME '.ai-tools\workloop-dashboard'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$htmlPath = Join-Path $OutDir 'index.html'

$rows = @()
foreach ($project in $resolvedProjects) {
  $pairsRoot = Join-Path (Get-AiRelayRoot $project) 'pairs'
  if (-not (Test-Path -LiteralPath $pairsRoot)) { continue }
  Get-ChildItem -LiteralPath $pairsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $rows += Get-WorkloopPairRow -ProjectRoot $project -PairDir $_.FullName
  }
}

$statusCounts = $rows | Group-Object Status | Sort-Object Name
$generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$cards = [System.Text.StringBuilder]::new()
foreach ($row in ($rows | Sort-Object ProjectName, PairId)) {
  $roundText = if ($row.Round) { "$($row.Round) / $($row.MaxRounds)" } else { '-' }
  $command = "/workloop $($row.PairId)"
  [void]$cards.AppendLine("<article class='pair-card status-$([regex]::Replace($row.StatusClass, '[^A-Za-z0-9_-]', '-'))'>")
  [void]$cards.AppendLine("<div class='pair-head'><div><h2>$(Encode-WorkloopHtml $row.PairId)</h2><p>$(Encode-WorkloopHtml $row.ProjectName)</p></div><span class='badge'>$(Encode-WorkloopHtml $row.Status)</span></div>")
  [void]$cards.AppendLine("<dl class='meta'>")
  [void]$cards.AppendLine("<div><dt>目标</dt><dd>$(Encode-WorkloopHtml $row.Goal)</dd></div>")
  [void]$cards.AppendLine("<div><dt>轮次</dt><dd>$(Encode-WorkloopHtml $roundText)</dd></div>")
  [void]$cards.AppendLine("<div><dt>最新裁决</dt><dd>$(Encode-WorkloopHtml $row.LastDecision)</dd></div>")
  [void]$cards.AppendLine("<div><dt>历史轮次</dt><dd>$(Encode-WorkloopHtml $row.HistoryCount)</dd></div>")
  [void]$cards.AppendLine("<div><dt>最后更新</dt><dd>$(Encode-WorkloopHtml $row.LastUpdated)</dd></div>")
  [void]$cards.AppendLine("<div><dt>Pair 目录</dt><dd><code>$(Encode-WorkloopHtml $row.PairDir)</code></dd></div>")
  [void]$cards.AppendLine("</dl>")
  [void]$cards.AppendLine("<section class='excerpt'><h3>下一步命令</h3><pre>$(Encode-WorkloopHtml $command)</pre></section>")
  if ($row.InboxExcerpt) { [void]$cards.AppendLine("<section class='excerpt'><h3>最新任务</h3><pre>$(Encode-WorkloopHtml $row.InboxExcerpt)</pre></section>") }
  if ($row.ReportExcerpt) { [void]$cards.AppendLine("<section class='excerpt'><h3>最新报告</h3><pre>$(Encode-WorkloopHtml $row.ReportExcerpt)</pre></section>") }
  if ($row.ReplyExcerpt) { [void]$cards.AppendLine("<section class='excerpt'><h3>最新裁决</h3><pre>$(Encode-WorkloopHtml $row.ReplyExcerpt)</pre></section>") }
  [void]$cards.AppendLine("</article>")
}

$summary = [System.Text.StringBuilder]::new()
[void]$summary.AppendLine("<div class='summary-item'><strong>$($rows.Count)</strong><span>Pair 总数</span></div>")
[void]$summary.AppendLine("<div class='summary-item'><strong>$($resolvedProjects.Count)</strong><span>项目总数</span></div>")
foreach ($group in $statusCounts) {
  [void]$summary.AppendLine("<div class='summary-item'><strong>$($group.Count)</strong><span>$(Encode-WorkloopHtml $group.Name)</span></div>")
}

if ($rows.Count -eq 0) {
  [void]$cards.AppendLine("<section class='empty'>没有找到任何 .ai-relay/pairs。请传入包含 workloop 数据的项目目录。</section>")
}

$projectList = ($resolvedProjects | ForEach-Object { "<li><code>$(Encode-WorkloopHtml $_)</code></li>" }) -join "`n"

$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Agent Workloop Dashboard</title>
  <style>
    :root { color-scheme: light; --bg:#f7f7f4; --ink:#1f2933; --muted:#65717d; --line:#d8ddd8; --card:#ffffff; --accent:#176b5d; --warn:#a15c00; --danger:#a33a3a; --blue:#2d5f91; }
    * { box-sizing: border-box; }
    body { margin:0; font-family: "Segoe UI", system-ui, sans-serif; color:var(--ink); background:var(--bg); }
    header { padding:28px 36px 18px; border-bottom:1px solid var(--line); background:#fff; }
    h1 { margin:0 0 8px; font-size:28px; letter-spacing:0; }
    .sub { margin:0; color:var(--muted); font-size:14px; }
    main { padding:24px 36px 40px; }
    .summary { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; margin-bottom:22px; }
    .summary-item { background:#fff; border:1px solid var(--line); border-radius:8px; padding:14px 16px; }
    .summary-item strong { display:block; font-size:24px; margin-bottom:4px; }
    .summary-item span { color:var(--muted); font-size:13px; }
    .projects { margin:0 0 22px; padding:14px 18px; background:#fff; border:1px solid var(--line); border-radius:8px; }
    .projects h2 { font-size:15px; margin:0 0 10px; }
    .projects ul { margin:0; padding-left:18px; color:var(--muted); }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(360px,1fr)); gap:16px; }
    .pair-card { background:var(--card); border:1px solid var(--line); border-left:5px solid var(--muted); border-radius:8px; padding:16px; }
    .status-reply { border-left-color:var(--blue); }
    .status-report { border-left-color:var(--warn); }
    .status-inbox { border-left-color:var(--accent); }
    .status-running { border-left-color:var(--accent); }
    .status-stopped { border-left-color:var(--danger); }
    .status-completed { border-left-color:#5f7d38; }
    .pair-head { display:flex; justify-content:space-between; gap:12px; align-items:flex-start; margin-bottom:12px; }
    .pair-head h2 { margin:0; font-size:20px; }
    .pair-head p { margin:4px 0 0; color:var(--muted); font-size:13px; }
    .badge { white-space:nowrap; border:1px solid var(--line); border-radius:999px; padding:4px 9px; font-size:12px; background:#f9faf8; }
    .meta { display:grid; grid-template-columns:1fr 1fr; gap:10px 14px; margin:0 0 12px; }
    .meta div { min-width:0; }
    dt { color:var(--muted); font-size:12px; margin-bottom:2px; }
    dd { margin:0; font-size:13px; overflow-wrap:anywhere; }
    code { font-family: Consolas, monospace; font-size:12px; }
    .excerpt { border-top:1px solid var(--line); padding-top:10px; margin-top:10px; }
    .excerpt h3 { margin:0 0 6px; font-size:13px; color:var(--muted); }
    pre { margin:0; padding:10px; background:#f5f6f2; border:1px solid #e4e6df; border-radius:6px; white-space:pre-wrap; overflow-wrap:anywhere; font-family:Consolas, monospace; font-size:12px; line-height:1.45; }
    .empty { background:#fff; border:1px solid var(--line); border-radius:8px; padding:22px; color:var(--muted); }
    footer { color:var(--muted); font-size:12px; padding:0 36px 30px; }
  </style>
</head>
<body>
  <header>
    <h1>Agent Workloop Dashboard</h1>
    <p class="sub">只读面板。生成时间：$generatedAt。不会调用 Codex，不会控制终端，不会修改业务代码。</p>
  </header>
  <main>
    <section class="summary">
      $($summary.ToString())
    </section>
    <section class="projects">
      <h2>扫描项目</h2>
      <ul>$projectList</ul>
    </section>
    <section class="grid">
      $($cards.ToString())
    </section>
  </main>
  <footer>提示：复制卡片里的下一步命令到对应 Claude Code 会话执行。</footer>
</body>
</html>
"@

Set-Content -LiteralPath $htmlPath -Value $html -Encoding utf8

Write-Output "AI_WORKLOOP_DASHBOARD=$htmlPath"
Write-Output "AI_WORKLOOP_PROJECTS=$($resolvedProjects.Count)"
Write-Output "AI_WORKLOOP_PAIRS=$($rows.Count)"

if ($Open) {
  Start-Process $htmlPath
}
