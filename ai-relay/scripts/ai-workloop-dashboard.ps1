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

function Get-WorkloopSummaryInfo {
  param([string]$PairDir, [datetime]$LastSourceTime)
  $summaryDir = Join-Path (Join-Path $PairDir 'summary') 'cc'
  $summaryPath = Join-Path $summaryDir 'workloop-summary-latest.md'
  $htmlPath = Join-Path $summaryDir 'workloop-summary-latest.html'
  if (-not (Test-Path -LiteralPath $summaryPath)) {
    return [pscustomobject]@{
      State = 'missing'
      Label = '未生成'
      Path = $summaryPath
      HtmlPath = $htmlPath
      Excerpt = ''
    }
  }
  $item = Get-Item -LiteralPath $summaryPath
  $state = 'fresh'
  $label = '可用'
  if ($LastSourceTime -and $item.LastWriteTime -lt $LastSourceTime) {
    $state = 'stale'
    $label = '已过期'
  }
  $text = Read-WorkloopText $summaryPath
  $excerpt = ''
  if ($text) {
    $lines = @($text -split "`r?`n" | Where-Object {
      $line = $_.Trim()
      $line -and
        $line -notmatch '^#' -and
        $line -notmatch '^- Pair:' -and
        $line -notmatch '^- 项目:' -and
        $line -notmatch '^- 生成时间:' -and
        $line -notmatch '^- 分析方式:'
    })
    if ($lines.Count -gt 0) {
      $excerpt = ($lines | Select-Object -First 4) -join "`n"
      if ($excerpt.Length -gt 260) { $excerpt = $excerpt.Substring(0, 260) + '...' }
    }
  }
  [pscustomobject]@{
    State = $state
    Label = $label
    Path = $summaryPath
    HtmlPath = $htmlPath
    Excerpt = $excerpt
  }
}

function Get-WorkloopPrimaryState {
  param(
    [bool]$UnreadReply,
    [bool]$UnreadInbox,
    [bool]$ReportReady,
    $GoalJson,
    $RunnerStatus,
    [string]$SummaryState,
    [int]$HistoryCount
  )

  if ($RunnerStatus -and $RunnerStatus.status -eq 'failed') {
    return [pscustomobject]@{
      Priority = 10
      State = 'failed'
      Label = '执行异常'
      Action = '查看状态'
      Detail = 'CC runner 失败或状态过期，需要先看错误。'
    }
  }
  if ($GoalJson -and $GoalJson.status -eq 'stopped') {
    return [pscustomobject]@{
      Priority = 20
      State = 'blocked_user'
      Label = '需要你介入'
      Action = '查看总结'
      Detail = if ($GoalJson.stopReason) { [string]$GoalJson.stopReason } else { 'Workloop 已停止，需要人工判断下一步。' }
    }
  }
  if ($RunnerStatus -and $RunnerStatus.status -in @('queued','started','running')) {
    return [pscustomobject]@{
      Priority = 30
      State = 'running'
      Label = '正在运行'
      Action = '查看状态'
      Detail = 'Claude Code 正在执行或终端已启动。'
    }
  }
  if ($ReportReady) {
    return [pscustomobject]@{
      Priority = 40
      State = 'report_ready'
      Label = '待 Codex 审核'
      Action = '送审'
      Detail = 'cc-report.md 已就绪且新于 codex-reply.md。'
    }
  }
  if ($UnreadReply) {
    return [pscustomobject]@{
      Priority = 50
      State = 'reply_unread'
      Label = '待 CC 执行裁决'
      Action = '继续'
      Detail = '有未读 Codex 裁决。'
    }
  }
  if ($UnreadInbox) {
    return [pscustomobject]@{
      Priority = 60
      State = 'inbox_unread'
      Label = '待 CC 执行任务'
      Action = '继续'
      Detail = '有未读任务。'
    }
  }
  if ($SummaryState -in @('missing','stale') -and $HistoryCount -gt 0) {
    return [pscustomobject]@{
      Priority = 75
      State = 'summary_stale'
      Label = '建议看总结'
      Action = '查看总结'
      Detail = '已有历史轮次，但总结不存在或已过期。'
    }
  }
  if ($GoalJson -and $GoalJson.status -eq 'completed') {
    return [pscustomobject]@{
      Priority = 90
      State = 'completed'
      Label = '已完成'
      Action = '查看总结'
      Detail = '目标已完成，可复盘或归档。'
    }
  }
  return [pscustomobject]@{
    Priority = 100
    State = 'idle'
    Label = '空闲'
    Action = '规划任务'
    Detail = '当前没有待处理消息。'
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
  $nextSource = '无'
  $sourceText = ''
  if ($reportReady) {
    $nextSource = 'cc-report.md -> Codex'
    $sourceText = Read-WorkloopText $reportPath
  } elseif ($unreadReply) {
    $nextSource = 'codex-reply.md'
    $sourceText = Read-WorkloopText $replyPath
  } elseif ($unreadInbox) {
    $nextSource = 'cc-inbox.md'
    $sourceText = Read-WorkloopText $inboxPath
  }
  $sourceChars = if ($sourceText) { $sourceText.Length } else { 0 }
  $runnerStatusText = if ($runnerStatus -and $runnerStatus.status) { [string]$runnerStatus.status } else { '' }
  $runnerUpdatedAt = if ($runnerStatus -and $runnerStatus.updatedAt) { [string]$runnerStatus.updatedAt } else { '' }

  $reply = Read-WorkloopText $replyPath
  $lastTime = @($reportTime, $replyTime, (Get-WorkloopFileTime $inboxPath)) |
    Where-Object { $_ } |
    Sort-Object -Descending |
    Select-Object -First 1
  $health = Get-WorkloopHealth -UnreadReply $unreadReply -UnreadInbox $unreadInbox -ReportReady $reportReady -GoalJson $goalJson -LastTime $lastTime -HistoryCount $historyCount
  $summaryInfo = Get-WorkloopSummaryInfo -PairDir $PairDir -LastSourceTime $lastTime
  $primary = Get-WorkloopPrimaryState -UnreadReply $unreadReply -UnreadInbox $unreadInbox -ReportReady $reportReady -GoalJson $goalJson -RunnerStatus $runnerStatus -SummaryState $summaryInfo.State -HistoryCount $historyCount
  $focusText = if ($summaryInfo.Excerpt) { $summaryInfo.Excerpt } elseif ($reply) { Get-WorkloopExcerpt $replyPath 260 } elseif ($report) { Get-WorkloopExcerpt $reportPath 260 } elseif (Read-WorkloopText $inboxPath) { Get-WorkloopExcerpt $inboxPath 260 } else { $primary.Detail }

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
    Priority = $primary.Priority
    PrimaryState = $primary.State
    PrimaryLabel = $primary.Label
    PrimaryAction = $primary.Action
    PrimaryDetail = $primary.Detail
    FocusText = $focusText
    SummaryState = $summaryInfo.State
    SummaryLabel = $summaryInfo.Label
    SummaryPath = $summaryInfo.Path
    SummaryHtmlPath = $summaryInfo.HtmlPath
    LastUpdated = if ($lastTime) { $lastTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
    HistoryCount = $historyCount
    CcRunnerStatus = $runnerStatusText
    CcRunnerUpdatedAt = $runnerUpdatedAt
    CcRunnerSource = $nextSource
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
$controlPrefix = ''
if ($ControlBaseUrl) {
  $controlPrefix = $ControlBaseUrl.TrimEnd('/')
}

$cards = [System.Text.StringBuilder]::new()
$sortedRows = @($rows | Sort-Object Priority, ProjectName, PairId)
foreach ($row in $sortedRows) {
  $roundText = if ($row.Round) { "$($row.Round) / $($row.MaxRounds)" } else { '-' }
  $command = "/workloop $($row.PairId)"
  $psCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File `"`$env:USERPROFILE\.ai-tools\bin\ai-workloop.ps1`" `"$($row.PairId)`""
  [void]$cards.AppendLine("<article class='pair-card state-$([regex]::Replace($row.PrimaryState, '[^A-Za-z0-9_-]', '-')) health-$([regex]::Replace($row.HealthLevel, '[^A-Za-z0-9_-]', '-'))'>")
  [void]$cards.AppendLine("<div class='pair-head'><div><h2>$(Encode-WorkloopHtml $row.PairId)</h2><p>$(Encode-WorkloopHtml $row.ProjectName)</p></div><span class='badge'>$(Encode-WorkloopHtml $row.PrimaryLabel)</span></div>")
  [void]$cards.AppendLine("<section class='pair-focus'><dl>")
  [void]$cards.AppendLine("<div><dt>目标</dt><dd>$(Encode-WorkloopHtml $(if ($row.Goal) { $row.Goal } elseif ($row.Task) { $row.Task } else { '未设置' }))</dd></div>")
  [void]$cards.AppendLine("<div><dt>状态说明</dt><dd>$(Encode-WorkloopHtml $row.PrimaryDetail)</dd></div>")
  [void]$cards.AppendLine("<div><dt>当前结论</dt><dd>$(Encode-WorkloopHtml $row.FocusText)</dd></div>")
  [void]$cards.AppendLine("</dl></section>")
  [void]$cards.AppendLine("<dl class='compact-meta'>")
  [void]$cards.AppendLine("<div><dt>轮次</dt><dd>$(Encode-WorkloopHtml $roundText)</dd></div>")
  [void]$cards.AppendLine("<div><dt>最新裁决</dt><dd>$(Encode-WorkloopHtml $(if ($row.LastDecision) { $row.LastDecision } else { '-' }))</dd></div>")
  [void]$cards.AppendLine("<div><dt>总结</dt><dd>$(Encode-WorkloopHtml $row.SummaryLabel)</dd></div>")
  [void]$cards.AppendLine("<div><dt>最后更新</dt><dd>$(Encode-WorkloopHtml $(if ($row.LastUpdated) { $row.LastUpdated } else { '-' }))</dd></div>")
  [void]$cards.AppendLine("</dl>")
  [void]$cards.AppendLine("<section class='actions primary-actions' aria-label='主要操作'>")
  if ($controlPrefix) {
    $projectArg = Encode-WorkloopUrl $row.ProjectRoot
    $pairArg = Encode-WorkloopUrl $row.PairId
    $projectPathArg = Encode-WorkloopUrl $row.ProjectRoot
    $pairPathArg = Encode-WorkloopUrl $row.PairDir
    $reportPathArg = Encode-WorkloopUrl $row.ReportPath
    $replyPathArg = Encode-WorkloopUrl $row.ReplyPath
    $historyPathArg = Encode-WorkloopUrl $row.HistoryDir
    if ($row.PrimaryState -in @('report_ready','reply_unread','inbox_unread','running','failed','blocked_user')) {
      [void]$cards.AppendLine("<button type='button' class='danger-action main-action' data-confirm='按状态机继续：可能送 Codex 裁决，或调用 Claude CLI 执行未读任务/裁决。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/cc-runner?projectRoot=$projectArg&pair=$pairArg")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/cc-runner?projectRoot=$projectArg&pair=$pairArg")'>$(Encode-WorkloopHtml $row.PrimaryAction)</button>")
    } elseif ($row.PrimaryState -eq 'idle') {
      [void]$cards.AppendLine("<button type='button' class='main-action' data-plan-task='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-goal='$(Encode-WorkloopHtml $row.Goal)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/plan-task?projectRoot=$projectArg&pair=$pairArg")'>规划任务</button>")
    }
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=cc&cache=1")'>查看总结</button>")
    if ($row.PrimaryState -eq 'summary_stale') {
      [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='将调用 Claude Code 重新分析当前项目和 pair 数据，可能消耗 Claude Code 额度。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=cc&force=1")'>重新生成总结</button>")
    }
    [void]$cards.AppendLine("</section>")
    [void]$cards.AppendLine("<details class='debug-actions'><summary>详情 / 更多操作</summary>")
    [void]$cards.AppendLine("<dl class='meta'>")
    [void]$cards.AppendLine("<div><dt>原始状态</dt><dd>$(Encode-WorkloopHtml $row.Status)</dd></div>")
    [void]$cards.AppendLine("<div><dt>历史轮次</dt><dd>$(Encode-WorkloopHtml $row.HistoryCount)</dd></div>")
    [void]$cards.AppendLine("<div><dt>CC 会话</dt><dd><code>$(Encode-WorkloopHtml $row.CcSessionId)</code></dd></div>")
    [void]$cards.AppendLine("<div><dt>Runner 状态</dt><dd>$(Encode-WorkloopHtml $row.CcRunnerStatus) $(Encode-WorkloopHtml $row.CcRunnerUpdatedAt)</dd></div>")
    [void]$cards.AppendLine("<div><dt>读取来源</dt><dd>$(Encode-WorkloopHtml $row.CcRunnerSource)</dd></div>")
    [void]$cards.AppendLine("<div><dt>任务字符数</dt><dd>$(Encode-WorkloopHtml $row.CcRunnerSourceChars)</dd></div>")
    [void]$cards.AppendLine("<div><dt>Pair 目录</dt><dd><code>$(Encode-WorkloopHtml $row.PairDir)</code></dd></div>")
    [void]$cards.AppendLine("</dl>")
    [void]$cards.AppendLine("<div class='actions'>")
    [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='执行 /workloop 可能调用 Codex 并消耗额度。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/workloop?projectRoot=$projectArg&pair=$pairArg")'>执行 /workloop</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$pairPathArg")'>打开 Pair</button>")
    if (Test-Path -LiteralPath $row.ReportPath) { [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$reportPathArg")'>打开报告</button>") }
    if (Test-Path -LiteralPath $row.ReplyPath) { [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$replyPathArg")'>打开裁决</button>") }
    [void]$cards.AppendLine("<button type='button' data-plan-task='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-goal='$(Encode-WorkloopHtml $row.Goal)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/plan-task?projectRoot=$projectArg&pair=$pairArg")'>让 Codex 规划任务</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/codex-terminal?projectRoot=$projectArg&pair=$pairArg")'>打开 Codex 终端</button>")
    [void]$cards.AppendLine("<button type='button' data-rebind-codex='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/rebind-codex?projectRoot=$projectArg&pair=$pairArg")'>绑定/重绑 Codex</button>")
    [void]$cards.AppendLine("<button type='button' data-rebind-cc='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/rebind-cc?projectRoot=$projectArg&pair=$pairArg")'>绑定/重绑 CC</button>")
    [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='归档 Pair 会把目录移动到 .ai-relay/archived-pairs，不会删除数据。确认归档？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/archive-pair?projectRoot=$projectArg&pair=$pairArg")' data-refresh='true'>归档 Pair</button>")
    [void]$cards.AppendLine("<button type='button' data-copy='$(Encode-WorkloopHtml $command)'>复制 /workloop</button>")
    [void]$cards.AppendLine("<button type='button' data-copy='$(Encode-WorkloopHtml $psCommand)'>复制 PowerShell</button>")
    [void]$cards.AppendLine("<button type='button' data-copy='$(Encode-WorkloopHtml $row.PairDir)'>复制 Pair 路径</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$projectPathArg")'>打开项目</button>")
    if (Test-Path -LiteralPath $row.HistoryDir) { [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$historyPathArg")'>打开 History</button>") }
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/export?projectRoot=$projectArg&pair=$pairArg")'>生成审计</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/review?projectRoot=$projectArg&pair=$pairArg")'>生成复盘</button>")
    [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='将调用 Claude Code 重新分析当前项目和 pair 数据，可能消耗 Claude Code 额度。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=cc&force=1")'>重新生成总结（CC）</button>")
    [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='将调用 Codex read-only 重新分析当前项目和 pair 数据，可能消耗 Codex 额度。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=codex&force=1")'>重新生成总结（Codex）</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=local&force=1")'>重新生成本地摘要</button>")
    [void]$cards.AppendLine("</div></details>")
  }
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
  if ($row.PrimaryState -notin @('completed','idle') -and $row.ReplyExcerpt) { [void]$cards.AppendLine("<section class='excerpt'><h3>最新裁决</h3><pre>$(Encode-WorkloopHtml $row.ReplyExcerpt)</pre></section>") }
  [void]$cards.AppendLine("</article>")
}

$summary = [System.Text.StringBuilder]::new()
[void]$summary.AppendLine("<div class='summary-item'><strong>$($rows.Count)</strong><span>Pair 总数</span></div>")
[void]$summary.AppendLine("<div class='summary-item'><strong>$($resolvedProjects.Count)</strong><span>项目总数</span></div>")
$actionCount = @($rows | Where-Object { $_.Priority -le 70 }).Count
$watchCount = @($rows | Where-Object { $_.Priority -gt 70 -and $_.HealthLevel -eq 'watch' }).Count
[void]$summary.AppendLine("<div class='summary-item action'><strong>$actionCount</strong><span>需要处理</span></div>")
[void]$summary.AppendLine("<div class='summary-item watch'><strong>$watchCount</strong><span>需要关注</span></div>")
foreach ($group in $statusCounts) {
  [void]$summary.AppendLine("<div class='summary-item'><strong>$($group.Count)</strong><span>$(Encode-WorkloopHtml $group.Name)</span></div>")
}

$actionBoard = [System.Text.StringBuilder]::new()
$actionRows = @($sortedRows | Where-Object { $_.Priority -le 70 } | Select-Object -First 8)
if ($actionRows.Count -gt 0) {
  [void]$actionBoard.AppendLine("<section class='action-board'><div class='section-head'><h2>需要你处理</h2><span>$($actionRows.Count)</span></div>")
  foreach ($row in $actionRows) {
    $projectArg = Encode-WorkloopUrl $row.ProjectRoot
    $pairArg = Encode-WorkloopUrl $row.PairId
    [void]$actionBoard.AppendLine("<article class='action-row state-$([regex]::Replace($row.PrimaryState, '[^A-Za-z0-9_-]', '-'))'>")
    [void]$actionBoard.AppendLine("<div><strong>$(Encode-WorkloopHtml $row.PairId)</strong><span>$(Encode-WorkloopHtml $row.ProjectName)</span></div>")
    [void]$actionBoard.AppendLine("<p><b>$(Encode-WorkloopHtml $row.PrimaryLabel)</b>：$(Encode-WorkloopHtml $row.PrimaryDetail)</p>")
    [void]$actionBoard.AppendLine("<p class='muted'>$(Encode-WorkloopHtml $row.FocusText)</p>")
    if ($controlPrefix) {
      [void]$actionBoard.AppendLine("<div class='actions compact-actions'>")
      if ($row.PrimaryState -in @('report_ready','reply_unread','inbox_unread','running','failed','blocked_user')) {
        [void]$actionBoard.AppendLine("<button type='button' class='danger-action' data-confirm='按状态机继续：可能送 Codex 裁决，或调用 Claude CLI 执行未读任务/裁决。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/cc-runner?projectRoot=$projectArg&pair=$pairArg")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/cc-runner?projectRoot=$projectArg&pair=$pairArg")'>$(Encode-WorkloopHtml $row.PrimaryAction)</button>")
      }
      [void]$actionBoard.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=cc&cache=1")'>查看总结</button>")
      [void]$actionBoard.AppendLine("</div>")
    }
    [void]$actionBoard.AppendLine("</article>")
  }
  [void]$actionBoard.AppendLine("</section>")
} else {
  [void]$actionBoard.AppendLine("<section class='action-board empty-board'><div class='section-head'><h2>需要你处理</h2><span>0</span></div><p>当前没有必须介入的 pair。</p></section>")
}

if ($rows.Count -eq 0) {
  [void]$cards.AppendLine("<section class='empty'>没有找到任何 .ai-relay/pairs。请传入包含 workloop 数据的项目目录。</section>")
}

$projectList = ($resolvedProjects | ForEach-Object { "<li><code>$(Encode-WorkloopHtml $_)</code></li>" }) -join "`n"
$createPanel = ''
if ($controlPrefix) {
  $projectOptions = ($resolvedProjects | ForEach-Object {
    $encoded = Encode-WorkloopHtml $_
    "<option value='$encoded'>$encoded</option>"
  }) -join "`n"
  $createPanel = @"
    <section class="create-panel">
      <h2>创建 Pair</h2>
      <form id="discover-projects-form" method="post" action="$(Encode-WorkloopHtml "$controlPrefix/action/discover-projects")">
        <label>扫描根目录
          <input name="scanRoot" value="E:\work\project" required>
        </label>
        <label>深度
          <input name="depth" type="number" min="1" max="5" value="2" required>
        </label>
        <button type="submit">扫描并添加项目</button>
      </form>
      <form id="create-pair-form" method="post" action="$(Encode-WorkloopHtml "$controlPrefix/action/create-pair")">
        <label>项目
          <select name="projectRoot" required>$projectOptions</select>
        </label>
        <label>Pair
          <input name="pair" required pattern="[A-Za-z0-9][A-Za-z0-9._-]*" placeholder="例如 com_main">
        </label>
        <label>目标
          <input name="task" placeholder="可选，写一句目标">
        </label>
        <label>Codex Session ID
          <input name="codexSessionId" placeholder="可选；留空则自动新建">
        </label>
        <label>Claude Code Session ID
          <input name="ccSessionId" placeholder="可选；留空则自动新建">
        </label>
        <button type="submit">创建 Pair</button>
      </form>
      <p>扫描会按 .git 和常见工程清单识别项目根；创建 Pair 时可填 Codex / Claude Code Session ID，留空会自动新建对应 session 后绑定。</p>
    </section>
"@
}

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
    .action-board { margin:0 0 22px; background:#fff; border:1px solid var(--line); border-radius:8px; padding:16px; }
    .section-head { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:12px; }
    .section-head h2 { margin:0; font-size:18px; }
    .section-head span { min-width:30px; text-align:center; border:1px solid var(--line); border-radius:999px; padding:3px 8px; color:var(--muted); }
    .action-row { display:grid; grid-template-columns:minmax(140px,220px) 1fr auto; gap:12px; align-items:start; border-top:1px solid var(--line); padding:12px 0; }
    .action-row:first-of-type { border-top:0; padding-top:0; }
    .action-row strong { display:block; font-size:15px; }
    .action-row span, .muted { color:var(--muted); font-size:12px; }
    .action-row p { margin:0; font-size:13px; overflow-wrap:anywhere; }
    .empty-board p { margin:0; color:var(--muted); }
    .projects { margin:0 0 22px; padding:14px 18px; background:#fff; border:1px solid var(--line); border-radius:8px; }
    .projects h2 { font-size:15px; margin:0 0 10px; }
    .projects ul { margin:0; padding-left:18px; color:var(--muted); }
    .create-panel { margin:0 0 22px; padding:14px 18px; background:#fff; border:1px solid var(--line); border-radius:8px; }
    .create-panel h2 { font-size:15px; margin:0 0 12px; }
    .create-panel form { display:grid; grid-template-columns:minmax(220px,1fr) minmax(160px,240px) minmax(220px,1fr) auto; gap:10px; align-items:end; margin-top:10px; }
    .create-panel label { display:grid; gap:5px; color:var(--muted); font-size:12px; }
    .create-panel input, .create-panel select { border:1px solid var(--line); border-radius:6px; padding:8px 10px; font:inherit; color:var(--ink); background:#fff; min-width:0; }
    .create-panel button { border:1px solid var(--accent); border-radius:6px; background:#e7f2ed; color:var(--accent); padding:8px 12px; font:inherit; cursor:pointer; }
    .create-panel p { margin:10px 0 0; color:var(--muted); font-size:12px; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(360px,1fr)); gap:16px; }
    .pair-card { background:var(--card); border:1px solid var(--line); border-left:5px solid var(--muted); border-radius:8px; padding:16px; }
    .state-failed, .state-blocked_user { border-left-color:var(--danger); }
    .state-report_ready, .state-summary_stale { border-left-color:var(--warn); }
    .state-reply_unread, .state-inbox_unread { border-left-color:var(--blue); }
    .state-running { border-left-color:var(--accent); }
    .state-completed { border-left-color:#5f7d38; }
    .health-action { box-shadow:0 0 0 1px rgba(161,92,0,.18); }
    .health-watch { box-shadow:0 0 0 1px rgba(45,95,145,.14); }
    .pair-head { display:flex; justify-content:space-between; gap:12px; align-items:flex-start; margin-bottom:12px; }
    .pair-head h2 { margin:0; font-size:20px; }
    .pair-head p { margin:4px 0 0; color:var(--muted); font-size:13px; }
    .badge { white-space:nowrap; border:1px solid var(--line); border-radius:999px; padding:4px 9px; font-size:12px; background:#f9faf8; }
    .pair-focus { border:1px solid var(--line); border-radius:8px; background:#fbfcfa; padding:12px; margin-bottom:12px; }
    .pair-focus dl { display:grid; gap:10px; margin:0; }
    .compact-meta, .meta { display:grid; grid-template-columns:1fr 1fr; gap:10px 14px; margin:0 0 12px; }
    .compact-meta div, .meta div { min-width:0; }
    dt { color:var(--muted); font-size:12px; margin-bottom:2px; }
    dd { margin:0; font-size:13px; overflow-wrap:anywhere; }
    code { font-family: Consolas, monospace; font-size:12px; }
    .actions { display:flex; flex-wrap:wrap; gap:8px; margin:12px 0; }
    .actions button, .actions a { appearance:none; border:1px solid var(--line); border-radius:6px; background:#fff; color:var(--ink); padding:7px 10px; font:inherit; font-size:12px; text-decoration:none; cursor:pointer; }
    .actions button:hover, .actions a:hover { border-color:var(--accent); color:var(--accent); }
    .actions button.copied { background:#e7f2ed; border-color:var(--accent); color:var(--accent); }
    .actions .danger-action { border-color:#d6b07b; background:#fff8ed; }
    .primary-actions { margin:10px 0 12px; }
    .actions .main-action { border-color:var(--accent); background:#e7f2ed; color:var(--accent); font-weight:600; }
    .compact-actions { margin:0; justify-content:flex-end; min-width:190px; }
    .debug-actions { border-top:1px solid var(--line); margin-top:10px; padding-top:10px; width:100%; }
    .debug-actions summary { cursor:pointer; color:var(--muted); font-size:12px; }
    .debug-actions .actions { margin:10px 0 0; }
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
    @media (max-width: 900px) {
      .create-panel form { grid-template-columns:1fr; }
      .action-row { grid-template-columns:1fr; }
      .compact-actions { justify-content:flex-start; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Agent Workloop Dashboard</h1>
    <p class="sub">本地控制面板。生成时间：$generatedAt。创建和归档只修改 .ai-relay 数据；执行按钮会调用对应 CLI。</p>
  </header>
  <main>
    <section class="summary">
      $($summary.ToString())
    </section>
    $($actionBoard.ToString())
    <section class="projects">
      <h2>扫描项目</h2>
      <ul>$projectList</ul>
    </section>
    $createPanel
    <section class="grid">
      $($cards.ToString())
    </section>
  </main>
  <footer>提示：创建 Pair 后，把 bind-request 交给对应 Codex 会话完成绑定。</footer>
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
        const statusUrl = button.getAttribute('data-status-url');
        const oldText = button.textContent;
        const resultWindow = window.open('', '_blank');
        let responseFinished = false;
        if (resultWindow) {
          resultWindow.document.open();
          const statusLink = statusUrl ? '<p><a href="' + statusUrl.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '">打开执行状态页</a></p>' : '';
          resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>正在启动</title><style>body{font-family:Segoe UI,system-ui,sans-serif;margin:24px;color:#1f2933;background:#f7f7f4}main{max-width:980px;margin:0 auto;background:#fff;border:1px solid #d8ddd8;border-radius:8px;padding:18px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f5f6f2;border:1px solid #e4e6df;border-radius:6px;padding:12px}a{color:#176b5d}</style></head><body><main><h1>正在启动</h1><pre>已发送请求，正在启动本地 Workloop 控制器和 Claude Code 终端。这个页面会自动切到状态页。</pre>' + statusLink + '</main></body></html>');
          resultWindow.document.close();
          if (statusUrl) {
            setTimeout(() => {
              if (!responseFinished && !resultWindow.closed) {
                resultWindow.location.href = statusUrl;
              }
            }, 1200);
          }
        }
        button.textContent = '执行中...';
        button.disabled = true;
        try {
          const response = await fetch(url, { method: 'POST' });
          const text = await response.text();
          responseFinished = true;
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write(text);
            resultWindow.document.close();
          } else {
            window.alert(text.replace(/<[^>]+>/g, ''));
          }
          if (button.getAttribute('data-refresh') === 'true' && response.ok) {
            setTimeout(() => window.location.reload(), 500);
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
    const createForm = document.getElementById('create-pair-form');
    if (createForm) {
      createForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const resultWindow = window.open('', '_blank');
        const data = new URLSearchParams(new FormData(createForm));
        try {
          const response = await fetch(createForm.action, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
            body: data.toString()
          });
          const text = await response.text();
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write(text);
            resultWindow.document.close();
          } else {
            window.alert(text.replace(/<[^>]+>/g, ''));
          }
          if (response.ok) {
            setTimeout(() => window.location.reload(), 500);
          }
        } catch (error) {
          const errorText = '创建失败：' + error;
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>创建失败</title></head><body><pre>' + errorText.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '</pre></body></html>');
            resultWindow.document.close();
          } else {
            window.alert(errorText);
          }
        }
      });
    }
    document.querySelectorAll('button[data-rebind-codex]').forEach((button) => {
      button.addEventListener('click', async () => {
        const pair = button.getAttribute('data-pair') || '';
        const projectRoot = button.getAttribute('data-project') || '';
        const url = button.getAttribute('data-url') || '';
        const codexSessionId = window.prompt('输入 Codex Session ID；留空会自动创建新的 Codex session 并绑定。', '');
        if (codexSessionId === null) return;
        const resultWindow = window.open('', '_blank');
        const data = new URLSearchParams();
        data.set('projectRoot', projectRoot);
        data.set('pair', pair);
        data.set('codexSessionId', codexSessionId);
        const oldText = button.textContent;
        button.textContent = '绑定中...';
        button.disabled = true;
        try {
          const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
            body: data.toString()
          });
          const text = await response.text();
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write(text);
            resultWindow.document.close();
          } else {
            window.alert(text.replace(/<[^>]+>/g, ''));
          }
          if (response.ok) {
            setTimeout(() => window.location.reload(), 500);
          }
        } catch (error) {
          const errorText = '绑定失败：' + error;
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>绑定失败</title></head><body><pre>' + errorText.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '</pre></body></html>');
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
    document.querySelectorAll('button[data-plan-task]').forEach((button) => {
      button.addEventListener('click', async () => {
        const pair = button.getAttribute('data-pair') || '';
        const projectRoot = button.getAttribute('data-project') || '';
        const url = button.getAttribute('data-url') || '';
        const currentGoal = button.getAttribute('data-goal') || '';
        const goal = window.prompt('输入目标，Codex 会先规划，再下发给 CC：', currentGoal);
        if (goal === null) return;
        const maxRoundsRaw = window.prompt('最大轮次：', '3');
        if (maxRoundsRaw === null) return;
        const resultWindow = window.open('', '_blank');
        const data = new URLSearchParams();
        data.set('projectRoot', projectRoot);
        data.set('pair', pair);
        data.set('goal', goal);
        data.set('maxRounds', maxRoundsRaw);
        const oldText = button.textContent;
        button.textContent = '规划中...';
        button.disabled = true;
        try {
          const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
            body: data.toString()
          });
          const text = await response.text();
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write(text);
            resultWindow.document.close();
          } else {
            window.alert(text.replace(/<[^>]+>/g, ''));
          }
          if (response.ok) {
            setTimeout(() => window.location.reload(), 500);
          }
        } catch (error) {
          const errorText = '设置失败：' + error;
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>设置失败</title></head><body><pre>' + errorText.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '</pre></body></html>');
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
    document.querySelectorAll('button[data-rebind-cc]').forEach((button) => {
      button.addEventListener('click', async () => {
        const pair = button.getAttribute('data-pair') || '';
        const projectRoot = button.getAttribute('data-project') || '';
        const url = button.getAttribute('data-url') || '';
        const ccSessionId = window.prompt('输入 Claude Code Session ID；留空会自动创建新的 Claude Code session 并绑定。', '');
        if (ccSessionId === null) return;
        const resultWindow = window.open('', '_blank');
        const data = new URLSearchParams();
        data.set('projectRoot', projectRoot);
        data.set('pair', pair);
        data.set('ccSessionId', ccSessionId);
        const oldText = button.textContent;
        button.textContent = '绑定中...';
        button.disabled = true;
        try {
          const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
            body: data.toString()
          });
          const text = await response.text();
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write(text);
            resultWindow.document.close();
          } else {
            window.alert(text.replace(/<[^>]+>/g, ''));
          }
          if (response.ok) {
            setTimeout(() => window.location.reload(), 500);
          }
        } catch (error) {
          const errorText = '绑定失败：' + error;
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>绑定失败</title></head><body><pre>' + errorText.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '</pre></body></html>');
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
    const discoverForm = document.getElementById('discover-projects-form');
    if (discoverForm) {
      discoverForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const resultWindow = window.open('', '_blank');
        const data = new URLSearchParams(new FormData(discoverForm));
        try {
          const response = await fetch(discoverForm.action, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
            body: data.toString()
          });
          const text = await response.text();
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write(text);
            resultWindow.document.close();
          } else {
            window.alert(text.replace(/<[^>]+>/g, ''));
          }
          if (response.ok) {
            setTimeout(() => window.location.reload(), 500);
          }
        } catch (error) {
          const errorText = '扫描失败：' + error;
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>扫描失败</title></head><body><pre>' + errorText.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '</pre></body></html>');
            resultWindow.document.close();
          } else {
            window.alert(errorText);
          }
        }
      });
    }
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
