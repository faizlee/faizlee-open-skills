param(
  [string[]]$ProjectRoot,
  [string]$OutDir,
  [string]$ControlBaseUrl,
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

function ConvertTo-WorkloopFileUri {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  try {
    return ([System.Uri]::new((Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath)).AbsoluteUri
  } catch {
    return ''
  }
}

function Encode-WorkloopUrl {
  param([string]$Text)
  [System.Uri]::EscapeDataString([string]$Text)
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

function Get-WorkloopHealth {
  param(
    [bool]$UnreadReply,
    [bool]$UnreadInbox,
    [bool]$ReportReady,
    $GoalJson,
    [datetime]$LastTime,
    [int]$HistoryCount
  )

  $issues = @()
  if ($UnreadReply) {
    $issues += '有未读 Codex 裁决，建议先让 Claude Code 执行 /workloop <pair>。'
  }
  if ($ReportReady) {
    $issues += 'cc-report.md 已就绪但尚未送审，建议执行 /workloop <pair>。'
  }
  if ($UnreadInbox) {
    $issues += '有未读任务，建议让 Claude Code 拉取执行。'
  }
  if ($GoalJson -and $GoalJson.status -eq 'running') {
    $round = 0
    $maxRounds = 0
    if ($GoalJson.round -ne $null) { $round = [int]$GoalJson.round }
    if ($GoalJson.maxRounds -ne $null) { $maxRounds = [int]$GoalJson.maxRounds }
    if ($maxRounds -gt 0 -and $round -ge ($maxRounds - 1)) {
      $issues += "接近最大轮次：$round / $maxRounds。"
    }
  }
  if ($LastTime) {
    $ageHours = ((Get-Date) - $LastTime).TotalHours
    if ($ageHours -ge 12 -and $GoalJson -and $GoalJson.status -eq 'running') {
      $issues += ('running 状态超过 {0:N1} 小时未更新。' -f $ageHours)
    }
  }
  if ($HistoryCount -ge 5 -and $GoalJson -and $GoalJson.status -eq 'running') {
    $issues += "历史轮次较多：$HistoryCount 轮，建议复盘是否进入低效循环。"
  }

  if (-not $issues) {
    return [pscustomobject]@{
      Level = 'ok'
      Label = '正常'
      Issues = @()
    }
  }
  $level = 'watch'
  if ($ReportReady -or $UnreadReply) { $level = 'action' }
  return [pscustomobject]@{
    Level = $level
    Label = if ($level -eq 'action') { '需要处理' } else { '需要关注' }
    Issues = $issues
  }
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
  $runnerStatusPath = Join-Path $PairDir 'cc-runner-status.json'
  $runnerStatus = Read-WorkloopJson $runnerStatusPath

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
  $sourceText = Read-WorkloopText $inboxPath
  $sourceChars = if ($sourceText) { $sourceText.Length } else { 0 }
  $runnerStatusText = if ($runnerStatus -and $runnerStatus.status) { [string]$runnerStatus.status } else { '' }
  $runnerUpdatedAt = if ($runnerStatus -and $runnerStatus.updatedAt) { [string]$runnerStatus.updatedAt } else { '' }

  $reply = Read-WorkloopText $replyPath
  $lastTime = @($reportTime, $replyTime, (Get-WorkloopFileTime $inboxPath)) |
    Where-Object { $_ } |
    Sort-Object -Descending |
    Select-Object -First 1
  $health = Get-WorkloopHealth -UnreadReply $unreadReply -UnreadInbox $unreadInbox -ReportReady $reportReady -GoalJson $goalJson -LastTime $lastTime -HistoryCount $historyCount

  [pscustomobject]@{
    ProjectRoot = $ProjectRoot
    ProjectName = Split-Path -Leaf $ProjectRoot
    PairId = $pairId
    Task = if ($pairJson) { [string]$pairJson.task } else { '' }
    Role = if ($pairJson) { [string]$pairJson.role } else { '' }
    CodexSessionId = if ($pairJson) { [string]$pairJson.codexSessionId } else { '' }
    CcSessionId = if ($pairJson) { [string]$pairJson.ccSessionId } else { '' }
    Goal = if ($goalJson) { [string]$goalJson.goal } else { '' }
    GoalStatus = if ($goalJson) { [string]$goalJson.status } else { '' }
    Round = if ($goalJson -and $goalJson.round -ne $null) { [string]$goalJson.round } else { '' }
    MaxRounds = if ($goalJson -and $goalJson.maxRounds -ne $null) { [string]$goalJson.maxRounds } else { '' }
    LastDecision = if ($goalJson -and $goalJson.lastDecision) { [string]$goalJson.lastDecision } else { Get-WorkloopDecision $reply }
    Status = $status
    StatusClass = $statusClass
    HealthLevel = $health.Level
    HealthLabel = $health.Label
    HealthIssues = @($health.Issues)
    LastUpdated = if ($lastTime) { $lastTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
    HistoryCount = $historyCount
    CcRunnerStatus = $runnerStatusText
    CcRunnerUpdatedAt = $runnerUpdatedAt
    CcRunnerSource = 'cc-inbox.md'
    CcRunnerSourceChars = $sourceChars
    CcRunnerBudget = '不设置上限'
    PairDir = $PairDir
    HistoryDir = $historyRoot
    InboxPath = $inboxPath
    ReportPath = $reportPath
    ReplyPath = $replyPath
    InboxExcerpt = Get-WorkloopExcerpt $inboxPath
    ReportExcerpt = Get-WorkloopExcerpt $reportPath
    ReplyExcerpt = Get-WorkloopExcerpt $replyPath
  }
}

$workloopHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$dashboardConfigDir = Join-Path $workloopHome '.ai-tools\workloop-dashboard'
$projectConfigPath = Join-Path $dashboardConfigDir 'projects.json'

function Read-RegisteredWorkloopProjects {
  if (Test-Path -LiteralPath $projectConfigPath) {
    try {
      $data = Get-Content -LiteralPath $projectConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
      if ($data.projects) {
        return @($data.projects | ForEach-Object { [string]$_ })
      }
    } catch {
      Write-Warning "无法读取项目注册表：$projectConfigPath"
    }
  }
  return @()
}

if (-not $ProjectRoot -or $ProjectRoot.Count -eq 0) {
  $registeredProjects = @(Read-RegisteredWorkloopProjects)
  if ($registeredProjects.Count -gt 0) {
    $ProjectRoot = $registeredProjects
  } else {
    $ProjectRoot = @((Get-AiRelayProjectRoot))
  }
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
  $OutDir = $dashboardConfigDir
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
  $psCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File `"`$env:USERPROFILE\.ai-tools\bin\ai-workloop.ps1`" `"$($row.PairId)`""
  $projectUri = ConvertTo-WorkloopFileUri $row.ProjectRoot
  $pairUri = ConvertTo-WorkloopFileUri $row.PairDir
  $historyUri = ConvertTo-WorkloopFileUri $row.HistoryDir
  $reportUri = ConvertTo-WorkloopFileUri $row.ReportPath
  $replyUri = ConvertTo-WorkloopFileUri $row.ReplyPath
  $controlPrefix = ''
  if ($ControlBaseUrl) {
    $controlPrefix = $ControlBaseUrl.TrimEnd('/')
  }
  [void]$cards.AppendLine("<article class='pair-card status-$([regex]::Replace($row.StatusClass, '[^A-Za-z0-9_-]', '-')) health-$([regex]::Replace($row.HealthLevel, '[^A-Za-z0-9_-]', '-'))'>")
  [void]$cards.AppendLine("<div class='pair-head'><div><h2>$(Encode-WorkloopHtml $row.PairId)</h2><p>$(Encode-WorkloopHtml $row.ProjectName)</p></div><span class='badge'>$(Encode-WorkloopHtml $row.Status)</span></div>")
  [void]$cards.AppendLine("<dl class='meta'>")
  [void]$cards.AppendLine("<div><dt>目标</dt><dd>$(Encode-WorkloopHtml $row.Goal)</dd></div>")
  [void]$cards.AppendLine("<div><dt>轮次</dt><dd>$(Encode-WorkloopHtml $roundText)</dd></div>")
  [void]$cards.AppendLine("<div><dt>最新裁决</dt><dd>$(Encode-WorkloopHtml $row.LastDecision)</dd></div>")
  [void]$cards.AppendLine("<div><dt>历史轮次</dt><dd>$(Encode-WorkloopHtml $row.HistoryCount)</dd></div>")
  [void]$cards.AppendLine("<div><dt>CC 会话</dt><dd><code>$(Encode-WorkloopHtml $row.CcSessionId)</code></dd></div>")
  [void]$cards.AppendLine("<div><dt>Runner 状态</dt><dd>$(Encode-WorkloopHtml $row.CcRunnerStatus) $(Encode-WorkloopHtml $row.CcRunnerUpdatedAt)</dd></div>")
  [void]$cards.AppendLine("<div><dt>最后更新</dt><dd>$(Encode-WorkloopHtml $row.LastUpdated)</dd></div>")
  [void]$cards.AppendLine("<div><dt>Pair 目录</dt><dd><code>$(Encode-WorkloopHtml $row.PairDir)</code></dd></div>")
  [void]$cards.AppendLine("</dl>")
  [void]$cards.AppendLine("<section class='runner-preview'><h3>CC 执行预览</h3><dl>")
  [void]$cards.AppendLine("<div><dt>恢复会话</dt><dd><code>$(Encode-WorkloopHtml $row.CcSessionId)</code></dd></div>")
  [void]$cards.AppendLine("<div><dt>读取来源</dt><dd>$(Encode-WorkloopHtml $row.CcRunnerSource)</dd></div>")
  [void]$cards.AppendLine("<div><dt>任务字符数</dt><dd>$(Encode-WorkloopHtml $row.CcRunnerSourceChars)</dd></div>")
  [void]$cards.AppendLine("<div><dt>历史轮数</dt><dd>$(Encode-WorkloopHtml $row.HistoryCount)</dd></div>")
  [void]$cards.AppendLine("<div><dt>预算上限</dt><dd>$(Encode-WorkloopHtml $row.CcRunnerBudget)</dd></div>")
  [void]$cards.AppendLine("</dl></section>")
  [void]$cards.AppendLine("<section class='actions' aria-label='操作辅助'>")
  [void]$cards.AppendLine("<button type='button' data-copy='$(Encode-WorkloopHtml $command)'>复制 /workloop</button>")
  [void]$cards.AppendLine("<button type='button' data-copy='$(Encode-WorkloopHtml $psCommand)'>复制 PowerShell</button>")
  [void]$cards.AppendLine("<button type='button' data-copy='$(Encode-WorkloopHtml $row.PairDir)'>复制 Pair 路径</button>")
  if ($projectUri) { [void]$cards.AppendLine("<a href='$(Encode-WorkloopHtml $projectUri)'>打开项目</a>") }
  if ($pairUri) { [void]$cards.AppendLine("<a href='$(Encode-WorkloopHtml $pairUri)'>打开 Pair</a>") }
  if ($historyUri -and (Test-Path -LiteralPath $row.HistoryDir)) { [void]$cards.AppendLine("<a href='$(Encode-WorkloopHtml $historyUri)'>打开 History</a>") }
  if ($reportUri -and (Test-Path -LiteralPath $row.ReportPath)) { [void]$cards.AppendLine("<a href='$(Encode-WorkloopHtml $reportUri)'>打开报告</a>") }
  if ($replyUri -and (Test-Path -LiteralPath $row.ReplyPath)) { [void]$cards.AppendLine("<a href='$(Encode-WorkloopHtml $replyUri)'>打开裁决</a>") }
  if ($controlPrefix) {
    $projectArg = Encode-WorkloopUrl $row.ProjectRoot
    $pairArg = Encode-WorkloopUrl $row.PairId
    $pairPathArg = Encode-WorkloopUrl $row.PairDir
    [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='执行 /workloop 可能调用 Codex 并消耗额度。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/workloop?projectRoot=$projectArg&pair=$pairArg")'>执行 /workloop</button>")
    if ($row.CcSessionId) {
      [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='让 Claude Code 执行会调用 Claude CLI，可能修改文件并消耗额度，并会打开一个只读观看终端。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/cc-runner?projectRoot=$projectArg&pair=$pairArg")'>让 CC 执行并打开终端</button>")
    } else {
      [void]$cards.AppendLine("<button type='button' disabled title='pair.json 缺少 ccSessionId，需要重新 bind'>缺少 ccSessionId</button>")
    }
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$pairPathArg")'>系统打开 Pair</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/export?projectRoot=$projectArg&pair=$pairArg")'>生成审计</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/review?projectRoot=$projectArg&pair=$pairArg")'>生成复盘</button>")
  }
  [void]$cards.AppendLine("</section>")
  [void]$cards.AppendLine("<section class='health-box'><h3>健康提示：$(Encode-WorkloopHtml $row.HealthLabel)</h3>")
  if ($row.HealthIssues.Count -gt 0) {
    [void]$cards.AppendLine("<ul>")
    foreach ($issue in $row.HealthIssues) {
      [void]$cards.AppendLine("<li>$(Encode-WorkloopHtml $issue)</li>")
    }
    [void]$cards.AppendLine("</ul>")
  } else {
    [void]$cards.AppendLine("<p>暂无需要处理的事项。</p>")
  }
  [void]$cards.AppendLine("</section>")
  [void]$cards.AppendLine("<section class='excerpt'><h3>下一步命令</h3><pre>$(Encode-WorkloopHtml $command)</pre></section>")
  if ($row.InboxExcerpt) { [void]$cards.AppendLine("<section class='excerpt'><h3>最新任务</h3><pre>$(Encode-WorkloopHtml $row.InboxExcerpt)</pre></section>") }
  if ($row.ReportExcerpt) { [void]$cards.AppendLine("<section class='excerpt'><h3>最新报告</h3><pre>$(Encode-WorkloopHtml $row.ReportExcerpt)</pre></section>") }
  if ($row.ReplyExcerpt) { [void]$cards.AppendLine("<section class='excerpt'><h3>最新裁决</h3><pre>$(Encode-WorkloopHtml $row.ReplyExcerpt)</pre></section>") }
  [void]$cards.AppendLine("</article>")
}

$summary = [System.Text.StringBuilder]::new()
[void]$summary.AppendLine("<div class='summary-item'><strong>$($rows.Count)</strong><span>Pair 总数</span></div>")
[void]$summary.AppendLine("<div class='summary-item'><strong>$($resolvedProjects.Count)</strong><span>项目总数</span></div>")
$actionCount = @($rows | Where-Object { $_.HealthLevel -eq 'action' }).Count
$watchCount = @($rows | Where-Object { $_.HealthLevel -eq 'watch' }).Count
[void]$summary.AppendLine("<div class='summary-item action'><strong>$actionCount</strong><span>需要处理</span></div>")
[void]$summary.AppendLine("<div class='summary-item watch'><strong>$watchCount</strong><span>需要关注</span></div>")
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
    .health-action { box-shadow:0 0 0 1px rgba(161,92,0,.18); }
    .health-watch { box-shadow:0 0 0 1px rgba(45,95,145,.14); }
    .pair-head { display:flex; justify-content:space-between; gap:12px; align-items:flex-start; margin-bottom:12px; }
    .pair-head h2 { margin:0; font-size:20px; }
    .pair-head p { margin:4px 0 0; color:var(--muted); font-size:13px; }
    .badge { white-space:nowrap; border:1px solid var(--line); border-radius:999px; padding:4px 9px; font-size:12px; background:#f9faf8; }
    .meta { display:grid; grid-template-columns:1fr 1fr; gap:10px 14px; margin:0 0 12px; }
    .meta div { min-width:0; }
    dt { color:var(--muted); font-size:12px; margin-bottom:2px; }
    dd { margin:0; font-size:13px; overflow-wrap:anywhere; }
    code { font-family: Consolas, monospace; font-size:12px; }
    .actions { display:flex; flex-wrap:wrap; gap:8px; margin:12px 0; }
    .actions button, .actions a { appearance:none; border:1px solid var(--line); border-radius:6px; background:#fff; color:var(--ink); padding:7px 10px; font:inherit; font-size:12px; text-decoration:none; cursor:pointer; }
    .actions button:hover, .actions a:hover { border-color:var(--accent); color:var(--accent); }
    .actions button.copied { background:#e7f2ed; border-color:var(--accent); color:var(--accent); }
    .actions .danger-action { border-color:#d6b07b; background:#fff8ed; }
    .health-box { border-top:1px solid var(--line); margin-top:10px; padding-top:10px; }
    .runner-preview { border-top:1px solid var(--line); margin-top:10px; padding-top:10px; }
    .runner-preview h3 { margin:0 0 8px; font-size:13px; color:var(--muted); }
    .runner-preview dl { display:grid; grid-template-columns:1fr 1fr; gap:8px 12px; margin:0; }
    .health-box h3 { margin:0 0 6px; font-size:13px; color:var(--muted); }
    .health-box ul { margin:0; padding-left:18px; font-size:13px; }
    .health-box p { margin:0; color:var(--muted); font-size:13px; }
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
  <script>
    document.querySelectorAll('button[data-copy]').forEach((button) => {
      button.addEventListener('click', async () => {
        const text = button.getAttribute('data-copy') || '';
        try {
          await navigator.clipboard.writeText(text);
          button.classList.add('copied');
          const oldText = button.textContent;
          button.textContent = '已复制';
          setTimeout(() => {
            button.textContent = oldText;
            button.classList.remove('copied');
          }, 1200);
        } catch (error) {
          window.prompt('复制失败，请手动复制：', text);
        }
      });
    });
    document.querySelectorAll('button[data-post]').forEach((button) => {
      button.addEventListener('click', async () => {
        const message = button.getAttribute('data-confirm');
        if (message && !window.confirm(message)) return;
        const url = button.getAttribute('data-post');
        const oldText = button.textContent;
        const resultWindow = window.open('', '_blank');
        if (resultWindow) {
          resultWindow.document.open();
          resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>执行中</title><style>body{font-family:Segoe UI,system-ui,sans-serif;margin:24px;color:#1f2933;background:#f7f7f4}main{max-width:980px;margin:0 auto;background:#fff;border:1px solid #d8ddd8;border-radius:8px;padding:18px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f5f6f2;border:1px solid #e4e6df;border-radius:6px;padding:12px}</style></head><body><main><h1>正在执行</h1><pre>请求已发送到本地 Workloop 控制器，请等待结果返回。Claude Code 执行可能需要较长时间。</pre></main></body></html>');
          resultWindow.document.close();
        }
        button.textContent = '执行中...';
        button.disabled = true;
        try {
          const response = await fetch(url, { method: 'POST' });
          const text = await response.text();
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write(text);
            resultWindow.document.close();
          } else {
            window.alert(text.replace(/<[^>]+>/g, ''));
          }
        } catch (error) {
          const errorText = '执行失败：' + error;
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>执行失败</title></head><body><pre>' + errorText.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '</pre></body></html>');
            resultWindow.document.close();
          } else {
            window.alert(errorText);
          }
        } finally {
          button.textContent = oldText;
          button.disabled = false;
        }
      });
    });
  </script>
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
