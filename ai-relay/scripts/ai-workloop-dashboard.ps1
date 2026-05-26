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
  ConvertTo-AiRelayFileUri -ProjectRoot '' -Path $Path
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

function Get-WorkloopEffectiveRunnerStatus {
  param($StatusObject)

  $rawStatus = if ($StatusObject -and $StatusObject.status) { [string]$StatusObject.status } else { '' }
  $updatedAt = if ($StatusObject -and $StatusObject.updatedAt) { [string]$StatusObject.updatedAt } else { '' }
  $processId = if ($StatusObject -and $StatusObject.processId -ne $null) { [string]$StatusObject.processId } else { '' }
  $processAlive = if ($processId) { Test-AiRelayProcessAlive -ProcessId $processId } else { $false }
  $effectiveStatus = $rawStatus
  if ($rawStatus -in @('queued','started','running') -and -not $processAlive) {
    $effectiveStatus = 'stale'
  }

  return [pscustomobject]@{
    RawStatus = $rawStatus
    Status = $effectiveStatus
    UpdatedAt = $updatedAt
    ProcessId = $processId
    ProcessAlive = $processAlive
    IsActive = ($effectiveStatus -in @('queued','started','running') -and $processAlive)
    ForPrimary = if ($StatusObject) {
      [pscustomobject]@{
        status = $effectiveStatus
        rawStatus = $rawStatus
        updatedAt = $updatedAt
        processId = $processId
        processAlive = $processAlive
      }
    } else {
      $null
    }
  }
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

  if ($GoalJson -and $GoalJson.status -eq 'completed') {
    return [pscustomobject]@{
      Level = 'ok'
      Label = '已收口'
      Issues = @('目标已经完成；下一步通常是查看/生成总结、归档，或开新目标。')
    }
  }
  if ($GoalJson -and $GoalJson.status -eq 'stopped') {
    $reason = if ($GoalJson.stopReason) { [string]$GoalJson.stopReason } else { 'Workloop 已停止，需要人工判断下一步。' }
    return [pscustomobject]@{
      Level = 'action'
      Label = '需要介入'
      Issues = @($reason)
    }
  }

  $issues = @()
  if ($UnreadReply) {
    $issues += '有未读 Codex 裁决；如果目标仍在运行，面板会自动续跑并路由到 Claude Code 执行裁决。'
  }
  if ($ReportReady) {
    $issues += 'cc-report.md 已就绪但尚未送审；如果目标仍在运行，面板会自动续跑并送 Codex 审核。'
  }
  if ($UnreadInbox) {
    $issues += '有未读任务；如果目标仍在运行，面板会自动续跑并路由到 Claude Code 执行。'
  }
  if (-not $UnreadReply -and -not $UnreadInbox -and -not $ReportReady -and $GoalJson -and $GoalJson.status -in @('planned','running','started')) {
    $issues += '已设置最终目标但没有当前任务；面板会自动续跑并先让 Codex 规划下一步。'
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
  $expectedArtifactVersion = 'summary-html-artifact-v14'
  $summaryRoot = Join-Path $PairDir 'summary'
  $fallbackDir = Join-Path $summaryRoot 'cc'

  function New-SummaryCandidate {
    param([string]$Analyzer)
    $summaryDir = Join-Path $summaryRoot $Analyzer
    $summaryPath = Join-Path $summaryDir 'workloop-summary-latest.md'
    $htmlPath = Join-Path $summaryDir 'workloop-summary-latest.html'
    $statePath = Join-Path $summaryDir 'workloop-summary-state-latest.json'
    $metaPath = Join-Path $summaryDir 'workloop-summary-meta.json'
    $meta = Read-WorkloopJson $metaPath
    $stateDoc = Read-WorkloopJson $statePath
    $summaryState = if ($stateDoc -and $stateDoc.summaryState) { $stateDoc.summaryState } elseif ($meta -and $meta.summaryState) { $meta.summaryState } else { $null }
    $artifactVersion = if ($meta -and $meta.artifactVersion) { [string]$meta.artifactVersion } else { '' }
    $stateVersion = if ($stateDoc -and $stateDoc.artifactVersion) { [string]$stateDoc.artifactVersion } else { '' }
    $htmlExists = Test-Path -LiteralPath $htmlPath
    $mdExists = Test-Path -LiteralPath $summaryPath
    $artifactIsCurrent = $htmlExists -and $mdExists -and $summaryState -and ($artifactVersion -eq $expectedArtifactVersion) -and ($stateVersion -eq $expectedArtifactVersion)
    $artifactIsOld = $htmlExists -and -not $artifactIsCurrent
    $state = 'missing'
    $label = '未生成'
    $excerpt = ''
    $lastWrite = [datetime]::MinValue
    if ($mdExists) {
      $item = Get-Item -LiteralPath $summaryPath
      $lastWrite = $item.LastWriteTime
      $state = 'fresh'
      $label = if ($artifactIsCurrent) { '新版 HTML' } elseif ($artifactIsOld) { '旧版 HTML' } else { 'Markdown 可用' }
      if ($artifactIsCurrent -and $summaryState -and $summaryState.overall) {
        $label = [string]$summaryState.overall
      }
      if ($LastSourceTime -and $item.LastWriteTime -lt $LastSourceTime) {
        $state = 'stale'
        $label = if ($artifactIsOld) { '旧版且过期' } else { '已过期' }
      } elseif ($artifactIsOld -or -not $artifactIsCurrent) {
        $state = 'stale'
      }

      $text = Read-WorkloopText $summaryPath
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
    } elseif ($artifactIsOld) {
      $state = 'stale'
      $label = '旧版 HTML'
      $lastWrite = (Get-Item -LiteralPath $htmlPath).LastWriteTime
    }

    $stateScore = switch ($state) {
      'fresh' { 30 }
      'stale' { 10 }
      default { 0 }
    }
    $preference = switch ($Analyzer) {
      'cc' { 3 }
      'codex' { 2 }
      'local' { 1 }
      default { 0 }
    }
    $score = $stateScore + $(if ($artifactIsCurrent) { 8 } else { 0 }) + $(if ($summaryState) { 4 } else { 0 }) + $preference

    return [pscustomobject]@{
      Analyzer = $Analyzer
      State = $state
      Label = $label
      Path = $summaryPath
      HtmlPath = $htmlPath
      StatePath = $statePath
      Excerpt = $excerpt
      ArtifactVersion = $artifactVersion
      ArtifactCurrent = $artifactIsCurrent
      HtmlExists = $htmlExists
      Diagnosis = if ($summaryState -and $summaryState.diagnosis) { [string]$summaryState.diagnosis } else { '' }
      NeedsUser = if ($summaryState) { [bool]$summaryState.needsUser } else { $true }
      LastWriteTime = $lastWrite
      Score = $score
    }
  }

  $candidates = @('cc','codex','local') | ForEach-Object { New-SummaryCandidate -Analyzer $_ }
  $best = $candidates | Sort-Object Score, LastWriteTime -Descending | Select-Object -First 1
  if ($best -and $best.Score -gt 0) { return $best }

  return [pscustomobject]@{
    Analyzer = 'cc'
    State = 'missing'
    Label = '未生成'
    Path = (Join-Path $fallbackDir 'workloop-summary-latest.md')
    HtmlPath = (Join-Path $fallbackDir 'workloop-summary-latest.html')
    StatePath = (Join-Path $fallbackDir 'workloop-summary-state-latest.json')
    Excerpt = ''
    ArtifactVersion = ''
    ArtifactCurrent = $false
    HtmlExists = $false
    Diagnosis = ''
    NeedsUser = $true
    LastWriteTime = [datetime]::MinValue
    Score = 0
  }
}

function Get-WorkloopPrimaryState {
  param(
    [bool]$UnreadReply,
    [bool]$UnreadInbox,
    [bool]$ReportReady,
    $GoalJson,
    $RunnerStatus,
    $WorkloopRunnerStatus,
    [string]$SummaryState,
    [int]$HistoryCount
  )

  if ($WorkloopRunnerStatus -and $WorkloopRunnerStatus.status -eq 'failed') {
    return [pscustomobject]@{
      Priority = 8
      State = 'failed'
      Label = '执行异常'
      Action = '查看失败原因'
      Detail = 'Workloop runner 失败，需要先看输出。'
    }
  }
  if ($RunnerStatus -and $RunnerStatus.status -eq 'failed') {
    return [pscustomobject]@{
      Priority = 10
      State = 'failed'
      Label = '执行异常'
      Action = '查看失败原因'
      Detail = 'CC runner 失败或状态过期，需要先看错误。'
    }
  }
  if ($GoalJson -and $GoalJson.status -eq 'stopped') {
    return [pscustomobject]@{
      Priority = 20
      State = 'blocked_user'
      Label = '需要你介入'
      Action = '查看并收口'
      Detail = if ($GoalJson.stopReason) { [string]$GoalJson.stopReason } else { 'Workloop 已停止，需要人工判断下一步。' }
    }
  }
  if ($GoalJson -and $GoalJson.status -eq 'completed') {
    $lastNext = if ($GoalJson.lastNextInstruction) { [string]$GoalJson.lastNextInstruction } else { '' }
    $label = '已完成'
    $detail = '目标已完成，可复盘或归档。'
    if ($lastNext -match '等待用户|用户裁决|停止|不再继续|无需下一轮|当前用户目标已满足|是否要进入|提交产出|归档|开新') {
      $label = '已收口，待你选择'
      $detail = 'Codex 已接受并给出收口/等待用户信号；不应再派给 Claude Code，下一步是查看总结、归档，或开新目标。'
    }
    return [pscustomobject]@{
      Priority = 22
      State = 'completed'
      Label = $label
      Action = '查看总结 / 归档'
      Detail = $detail
    }
  }
  if ($ReportReady) {
    return [pscustomobject]@{
      Priority = 25
      State = 'report_ready'
      Label = '待 Codex 审核'
      Action = '送 Codex 审核'
      Detail = 'cc-report.md 已就绪且新于 codex-reply.md。'
    }
  }
  if ($UnreadReply) {
    return [pscustomobject]@{
      Priority = 30
      State = 'reply_unread'
      Label = '待 CC 执行裁决'
      Action = '让 CC 执行裁决'
      Detail = '有未读 Codex 裁决。'
    }
  }
  if ($UnreadInbox) {
    return [pscustomobject]@{
      Priority = 35
      State = 'inbox_unread'
      Label = '待 CC 执行任务'
      Action = '让 CC 执行任务'
      Detail = '有未读任务。'
    }
  }
  if ($WorkloopRunnerStatus -and $WorkloopRunnerStatus.status -in @('queued','started','running')) {
    return [pscustomobject]@{
      Priority = 45
      State = 'running'
      Label = '正在运行'
      Action = '查看运行中任务'
      Detail = 'Workloop runner 正在推进状态机。'
    }
  }
  if ($RunnerStatus -and $RunnerStatus.status -in @('queued','started','running')) {
    return [pscustomobject]@{
      Priority = 50
      State = 'running'
      Label = '正在运行'
      Action = '查看运行中任务'
      Detail = 'Claude Code 正在执行或终端已启动。'
    }
  }
  if ($GoalJson -and $GoalJson.status -in @('planned','running','started')) {
    return [pscustomobject]@{
      Priority = 60
      State = 'goal_ready'
      Label = '等待推进'
      Action = '开始 / 继续目标'
      Detail = '已设置最终目标，但当前没有待处理任务；下一步由 Codex 规划给 CC 的最小任务。'
    }
  }
  if ($SummaryState -in @('missing','stale') -and $HistoryCount -gt 0) {
    return [pscustomobject]@{
      Priority = 75
      State = 'summary_stale'
      Label = '建议看总结'
      Action = '更新总结'
      Detail = '已有历史轮次，但总结不存在或已过期。'
    }
  }
  return [pscustomobject]@{
    Priority = 100
    State = 'idle'
    Label = '空闲'
    Action = '设置目标'
    Detail = '当前没有最终目标和待处理消息。先设置一个最终目标，之后由系统自动规划和推进。'
  }
}

function Get-WorkloopPairRow {
  param([string]$ProjectRoot, [string]$PairDir)

  $pairId = Split-Path -Leaf $PairDir
  $pairJson = Read-WorkloopJson (Join-Path $PairDir 'pair.json')
  $goalJson = Read-WorkloopJson (Join-Path $PairDir 'goal.json')
  $pairTask = if ($pairJson) { [string]$pairJson.task } else { '' }
  if (-not $goalJson -and -not [string]::IsNullOrWhiteSpace($pairTask)) {
    $goalJson = [pscustomobject]@{
      goal = $pairTask.Trim()
      status = 'planned'
      round = 0
      maxRounds = 10
      inferredFromPairTask = $true
    }
  }
  $inboxPath = Join-Path $PairDir 'cc-inbox.md'
  $inboxReadPath = Join-Path $PairDir 'cc-inbox.read.md'
  $reportPath = Join-Path $PairDir 'cc-report.md'
  $replyPath = Join-Path $PairDir 'codex-reply.md'
  $replyReadPath = Join-Path $PairDir 'codex-reply.read.md'
  $historyRoot = Join-Path $PairDir 'history'
  $runnerStatusPath = Join-Path $PairDir 'cc-runner-status.json'
  $runnerStatus = Read-WorkloopJson $runnerStatusPath
  $workloopRunnerStatusPath = Join-Path $PairDir 'workloop-runner-status.json'
  $workloopRunnerStatus = Read-WorkloopJson $workloopRunnerStatusPath

  $unreadReply = Test-WorkloopUnread -SourcePath $replyPath -ReadPath $replyReadPath
  $unreadInbox = Test-WorkloopUnread -SourcePath $inboxPath -ReadPath $inboxReadPath
  $report = Read-WorkloopText $reportPath
  $hasReport = -not [string]::IsNullOrWhiteSpace($report)
  $reportTime = Get-WorkloopFileTime $reportPath
  $replyTime = Get-WorkloopFileTime $replyPath
  $reportReady = $hasReport -and $reportTime -and ((-not $replyTime) -or ($reportTime -gt $replyTime))

  $status = '空闲'
  $statusClass = 'idle'
  $runnerEffective = Get-WorkloopEffectiveRunnerStatus -StatusObject $runnerStatus
  $workloopRunnerEffective = Get-WorkloopEffectiveRunnerStatus -StatusObject $workloopRunnerStatus

  $workloopRunnerStatusText = $workloopRunnerEffective.Status
  if ($goalJson -and $goalJson.status -eq 'completed') {
    $status = '目标已完成'
    $statusClass = 'completed'
  } elseif ($goalJson -and $goalJson.status -eq 'stopped') {
    $status = '需要你介入'
    $statusClass = 'stopped'
  } elseif ($workloopRunnerStatusText -in @('queued','started','running')) {
    $status = 'Workloop 正在运行'
    $statusClass = 'running'
  } elseif ($unreadReply) {
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
  $runnerStatusText = $runnerEffective.Status
  $runnerUpdatedAt = $runnerEffective.UpdatedAt

  $reply = Read-WorkloopText $replyPath
  $lastTime = @($reportTime, $replyTime, (Get-WorkloopFileTime $inboxPath)) |
    Where-Object { $_ } |
    Sort-Object -Descending |
    Select-Object -First 1
  $health = Get-WorkloopHealth -UnreadReply $unreadReply -UnreadInbox $unreadInbox -ReportReady $reportReady -GoalJson $goalJson -LastTime $lastTime -HistoryCount $historyCount
  $summaryInfo = Get-WorkloopSummaryInfo -PairDir $PairDir -LastSourceTime $lastTime
  $primary = Get-WorkloopPrimaryState -UnreadReply $unreadReply -UnreadInbox $unreadInbox -ReportReady $reportReady -GoalJson $goalJson -RunnerStatus $runnerEffective.ForPrimary -WorkloopRunnerStatus $workloopRunnerEffective.ForPrimary -SummaryState $summaryInfo.State -HistoryCount $historyCount
  $focusText = if ($summaryInfo.Excerpt) { $summaryInfo.Excerpt } elseif ($reply) { Get-WorkloopExcerpt $replyPath 260 } elseif ($report) { Get-WorkloopExcerpt $reportPath 260 } elseif (Read-WorkloopText $inboxPath) { Get-WorkloopExcerpt $inboxPath 260 } else { $primary.Detail }
  $codexSessionId = if ($pairJson) { [string]$pairJson.codexSessionId } else { '' }
  $ccSessionId = if ($pairJson) { [string]$pairJson.ccSessionId } else { '' }
  $ccSessionName = if ($pairJson) { [string]$pairJson.ccSessionName } else { '' }
  $boundAt = if ($pairJson) { [string]$pairJson.boundAt } else { '' }
  $ccUsesNewTerminal = [string]::IsNullOrWhiteSpace($ccSessionId) -and -not [string]::IsNullOrWhiteSpace($ccSessionName) -and $ccSessionName.StartsWith('WT:')
  $missingFields = @()
  if (-not $pairJson) {
    $missingFields += 'pair.json'
  } else {
    if ([string]::IsNullOrWhiteSpace($codexSessionId)) { $missingFields += 'codexSessionId' }
    if ([string]::IsNullOrWhiteSpace($ccSessionId) -and -not $ccUsesNewTerminal) { $missingFields += 'ccSessionId' }
    if ([string]::IsNullOrWhiteSpace($ccSessionName)) { $missingFields += 'ccSessionName' }
    if ([string]::IsNullOrWhiteSpace($boundAt)) { $missingFields += 'boundAt' }
  }
  $bindingLabel = if ($missingFields.Count -gt 0) { '缺失：' + ($missingFields -join ', ') } else { '完整' }

  [pscustomobject]@{
    ProjectRoot = $ProjectRoot
    ProjectName = Split-Path -Leaf $ProjectRoot
    PairId = $pairId
    Task = $pairTask
    Role = if ($pairJson) { [string]$pairJson.role } else { '' }
    CodexSessionId = $codexSessionId
    CcSessionId = $ccSessionId
    CcSessionName = $ccSessionName
    CcUsesNewTerminal = $ccUsesNewTerminal
    BoundAt = $boundAt
    MissingFields = @($missingFields)
    BindingLabel = $bindingLabel
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
    SummaryAnalyzer = $summaryInfo.Analyzer
    SummaryState = $summaryInfo.State
    SummaryLabel = $summaryInfo.Label
    SummaryPath = $summaryInfo.Path
    SummaryHtmlPath = $summaryInfo.HtmlPath
    LastUpdated = if ($lastTime) { $lastTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
    HistoryCount = $historyCount
    CcRunnerStatus = $runnerStatusText
    CcRunnerUpdatedAt = $runnerUpdatedAt
    WorkloopRunnerStatus = $workloopRunnerStatusText
    WorkloopRunnerUpdatedAt = $workloopRunnerEffective.UpdatedAt
    WorkloopRunnerActive = [bool]$workloopRunnerEffective.IsActive
    AnyRunnerStatus = (@($workloopRunnerStatusText, $runnerStatusText) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
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
  $roundLabel = '轮次'
  if ($row.Round -and $row.MaxRounds -and [string]$row.Round -match '^\d+$' -and [string]$row.MaxRounds -match '^\d+$') {
    if ([int]$row.Round -gt [int]$row.MaxRounds) {
      $roundLabel = '历史轮次'
      $roundText = "$($row.Round) / $($row.MaxRounds)（旧版超出）"
    }
  }
  $isAttention = ($row.PrimaryState -in @('failed','blocked_user','report_ready','reply_unread','inbox_unread','summary_stale')) -or ($row.HealthLevel -eq 'action')
  $attentionClass = if ($isAttention) { ' needs-attention' } else { '' }
  $attentionAttr = if ($isAttention) {
    " data-needs-attention='true' data-attention-pair='$(Encode-WorkloopHtml $row.PairId)' data-attention-project='$(Encode-WorkloopHtml $row.ProjectName)' data-attention-label='$(Encode-WorkloopHtml $row.PrimaryLabel)' data-attention-action='$(Encode-WorkloopHtml $row.PrimaryAction)'"
  } else {
    ''
  }
  [void]$cards.AppendLine("<article class='pair-card state-$([regex]::Replace($row.PrimaryState, '[^A-Za-z0-9_-]', '-')) health-$([regex]::Replace($row.HealthLevel, '[^A-Za-z0-9_-]', '-'))$attentionClass'$attentionAttr>")
  [void]$cards.AppendLine("<div class='pair-head'><div><h2>$(Encode-WorkloopHtml $row.PairId)</h2><p>$(Encode-WorkloopHtml $row.ProjectName)</p></div><span class='badge'>$(Encode-WorkloopHtml $row.PrimaryLabel)</span></div>")
  if ($isAttention) {
    [void]$cards.AppendLine("<section class='attention-callout'><strong>需要你看这里</strong><span>$(Encode-WorkloopHtml $row.PrimaryDetail)</span><em>建议操作：$(Encode-WorkloopHtml $row.PrimaryAction)</em></section>")
  }
  [void]$cards.AppendLine("<section class='pair-focus'><dl>")
  [void]$cards.AppendLine("<div><dt>目标</dt><dd>$(Encode-WorkloopHtml $(if ($row.Goal) { $row.Goal } elseif ($row.Task) { $row.Task } else { '未设置' }))</dd></div>")
  [void]$cards.AppendLine("<div><dt>状态说明</dt><dd>$(Encode-WorkloopHtml $row.PrimaryDetail)</dd></div>")
  [void]$cards.AppendLine("<div><dt>当前结论</dt><dd>$(Encode-WorkloopHtml $row.FocusText)</dd></div>")
  [void]$cards.AppendLine("</dl></section>")
  [void]$cards.AppendLine("<dl class='compact-meta'>")
  [void]$cards.AppendLine("<div><dt>$(Encode-WorkloopHtml $roundLabel)</dt><dd>$(Encode-WorkloopHtml $roundText)</dd></div>")
  [void]$cards.AppendLine("<div><dt>最新裁决</dt><dd>$(Encode-WorkloopHtml $(if ($row.LastDecision) { $row.LastDecision } else { '-' }))</dd></div>")
  [void]$cards.AppendLine("<div><dt>总结</dt><dd>$(Encode-WorkloopHtml $row.SummaryLabel)</dd></div>")
  [void]$cards.AppendLine("<div><dt>最后更新</dt><dd>$(Encode-WorkloopHtml $(if ($row.LastUpdated) { $row.LastUpdated } else { '-' }))</dd></div>")
  [void]$cards.AppendLine("<div><dt>Runner</dt><dd>$(Encode-WorkloopHtml $(if ($row.AnyRunnerStatus) { $row.AnyRunnerStatus } else { '-' }))</dd></div>")
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
    $summaryAnalyzer = if ([string]::IsNullOrWhiteSpace($row.SummaryAnalyzer)) { 'cc' } else { [string]$row.SummaryAnalyzer }
    if ($row.PrimaryState -in @('running','failed')) {
      $runningStatusUrl = if ($row.WorkloopRunnerActive) { "$controlPrefix/status/workloop?projectRoot=$projectArg&pair=$pairArg" } else { "$controlPrefix/status/cc-runner?projectRoot=$projectArg&pair=$pairArg" }
      [void]$cards.AppendLine("<button type='button' class='main-action' data-open-url='$(Encode-WorkloopHtml $runningStatusUrl)'>$(Encode-WorkloopHtml $row.PrimaryAction)</button>")
    } elseif ($row.PrimaryState -eq 'blocked_user') {
      $primaryStatusUrl = "$controlPrefix/status/workloop?projectRoot=$projectArg&pair=$pairArg"
      [void]$cards.AppendLine("<button type='button' class='danger-action main-action' data-resume-goal='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-goal='$(Encode-WorkloopHtml $row.Goal)' data-round='$(Encode-WorkloopHtml $row.Round)' data-max-rounds='$(Encode-WorkloopHtml $row.MaxRounds)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/resume-goal?projectRoot=$projectArg&pair=$pairArg")' data-status-url='$(Encode-WorkloopHtml $primaryStatusUrl)'>续同一 Pair</button>")
    } elseif ($row.PrimaryState -in @('report_ready','reply_unread','inbox_unread','goal_ready')) {
      $primaryStatusUrl = "$controlPrefix/status/workloop?projectRoot=$projectArg&pair=$pairArg"
      $continueUrl = "$controlPrefix/action/continue-goal?projectRoot=$projectArg&pair=$pairArg"
      $autoAttr = ''
      if ($row.PrimaryState -in @('report_ready','reply_unread','inbox_unread','goal_ready') -and $row.GoalStatus -in @('running','started','planned') -and -not $row.WorkloopRunnerActive) {
        $autoKey = "$($row.ProjectRoot)|$($row.PairId)|$($row.PrimaryState)|$($row.LastUpdated)"
        $autoAttr = " data-auto-continue='true' data-auto-key='$(Encode-WorkloopHtml $autoKey)'"
      }
      [void]$cards.AppendLine("<button type='button' class='danger-action main-action' data-confirm='按状态机开始/继续：可能让 Codex 规划、送 Codex 审核，或调用 Claude CLI 执行任务。确认继续？' data-post='$(Encode-WorkloopHtml $continueUrl)' data-status-url='$(Encode-WorkloopHtml $primaryStatusUrl)'$autoAttr>$(Encode-WorkloopHtml $row.PrimaryAction)</button>")
    } elseif ($row.PrimaryState -eq 'idle') {
      [void]$cards.AppendLine("<button type='button' class='main-action' data-plan-task='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-goal='$(Encode-WorkloopHtml $row.Goal)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/plan-task?projectRoot=$projectArg&pair=$pairArg")'>设置最终目标</button>")
    }
    $summaryButtonText = if ($row.SummaryState -in @('missing','stale')) { '生成 / 更新总结' } else { '查看总结' }
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=$summaryAnalyzer&cache=1")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/summary?projectRoot=$projectArg&pair=$pairArg")'>$(Encode-WorkloopHtml $summaryButtonText)</button>")
    if ($row.PrimaryState -eq 'summary_stale') {
      [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='将调用 Claude Code 重新分析当前项目和 pair 数据，可能消耗 Claude Code 额度。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=cc&force=1")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/summary?projectRoot=$projectArg&pair=$pairArg")'>重新生成总结</button>")
    }
    [void]$cards.AppendLine("</section>")
    [void]$cards.AppendLine("<details class='debug-actions'><summary>详情 / 更多操作</summary>")
    [void]$cards.AppendLine("<dl class='meta'>")
    [void]$cards.AppendLine("<div><dt>原始状态</dt><dd>$(Encode-WorkloopHtml $row.Status)</dd></div>")
    [void]$cards.AppendLine("<div><dt>历史轮次</dt><dd>$(Encode-WorkloopHtml $row.HistoryCount)</dd></div>")
    [void]$cards.AppendLine("<div><dt>Runner 状态</dt><dd>Workloop: $(Encode-WorkloopHtml $row.WorkloopRunnerStatus) $(Encode-WorkloopHtml $row.WorkloopRunnerUpdatedAt)<br>CC: $(Encode-WorkloopHtml $row.CcRunnerStatus) $(Encode-WorkloopHtml $row.CcRunnerUpdatedAt)</dd></div>")
    [void]$cards.AppendLine("<div><dt>读取来源</dt><dd>$(Encode-WorkloopHtml $row.CcRunnerSource)</dd></div>")
    [void]$cards.AppendLine("<div><dt>任务字符数</dt><dd>$(Encode-WorkloopHtml $row.CcRunnerSourceChars)</dd></div>")
    [void]$cards.AppendLine("<div><dt>Pair 目录</dt><dd><code>$(Encode-WorkloopHtml $row.PairDir)</code></dd></div>")
    [void]$cards.AppendLine("</dl>")
    $codexDisplay = if ([string]::IsNullOrWhiteSpace($row.CodexSessionId)) { '<span class="missing">缺失</span>' } else { "<code>$(Encode-WorkloopHtml $row.CodexSessionId)</code>" }
    $ccDisplay = if ([string]::IsNullOrWhiteSpace($row.CcSessionId)) {
      if ($row.CcUsesNewTerminal) { '<span class="ok-text">未预绑定；执行时新开 Claude Code 终端</span>' } else { '<span class="missing">缺失</span>' }
    } else {
      "<code>$(Encode-WorkloopHtml $row.CcSessionId)</code>"
    }
    $ccNameDisplay = if ([string]::IsNullOrWhiteSpace($row.CcSessionName)) { '<span class="missing">缺失</span>' } else { "<code>$(Encode-WorkloopHtml $row.CcSessionName)</code>" }
    $roleDisplay = if ([string]::IsNullOrWhiteSpace($row.Role)) { '<span class="missing">缺失</span>' } else { Encode-WorkloopHtml $row.Role }
    $boundAtDisplay = if ([string]::IsNullOrWhiteSpace($row.BoundAt)) { '<span class="missing">缺失</span>' } else { Encode-WorkloopHtml $row.BoundAt }
    $missingDisplay = if ($row.MissingFields.Count -gt 0) { "<span class='missing'>$(Encode-WorkloopHtml ($row.MissingFields -join ', '))</span>" } else { '<span class="ok-text">无</span>' }
    [void]$cards.AppendLine("<section class='binding-box'><h3>绑定字段</h3><dl class='meta'>")
    [void]$cards.AppendLine("<div><dt>缺失项</dt><dd>$missingDisplay</dd></div>")
    [void]$cards.AppendLine("<div><dt>Codex session</dt><dd>$codexDisplay</dd></div>")
    [void]$cards.AppendLine("<div><dt>CC session</dt><dd>$ccDisplay</dd></div>")
    [void]$cards.AppendLine("<div><dt>CC session name</dt><dd>$ccNameDisplay</dd></div>")
    [void]$cards.AppendLine("<div><dt>role</dt><dd>$roleDisplay</dd></div>")
    [void]$cards.AppendLine("<div><dt>boundAt</dt><dd>$boundAtDisplay</dd></div>")
    [void]$cards.AppendLine("</dl></section>")
    [void]$cards.AppendLine("<div class='action-groups'>")
    [void]$cards.AppendLine("<section class='action-group action-group-primary'><h4>流程</h4><div class='actions'>")
    [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='按状态机开始/继续：可能让 Codex 规划、送 Codex 审核，或调用 Claude CLI 执行任务。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/continue-goal?projectRoot=$projectArg&pair=$pairArg")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/workloop?projectRoot=$projectArg&pair=$pairArg")'>开始 / 继续目标</button>")
    if ($row.PrimaryState -in @('blocked_user','completed') -or $row.GoalStatus -in @('stopped','completed')) {
      [void]$cards.AppendLine("<button type='button' class='danger-action' data-resume-goal='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-goal='$(Encode-WorkloopHtml $row.Goal)' data-round='$(Encode-WorkloopHtml $row.Round)' data-max-rounds='$(Encode-WorkloopHtml $row.MaxRounds)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/resume-goal?projectRoot=$projectArg&pair=$pairArg")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/workloop?projectRoot=$projectArg&pair=$pairArg")'>续同一 Pair</button>")
    }
    [void]$cards.AppendLine("<button type='button' data-plan-task='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-goal='$(Encode-WorkloopHtml $row.Goal)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/plan-task?projectRoot=$projectArg&pair=$pairArg")'>只让 Codex 规划下一步</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/codex-terminal?projectRoot=$projectArg&pair=$pairArg")'>打开 Codex 终端</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/cc-terminal?projectRoot=$projectArg&pair=$pairArg")'>打开 CC 原会话</button>")
    [void]$cards.AppendLine("</div></section>")
    [void]$cards.AppendLine("<section class='action-group'><h4>查看</h4><div class='actions'>")
    [void]$cards.AppendLine("<button type='button' data-open-url='$(Encode-WorkloopHtml "$controlPrefix/status/workloop?projectRoot=$projectArg&pair=$pairArg")'>查看 Workloop 输出</button>")
    [void]$cards.AppendLine("<button type='button' data-open-url='$(Encode-WorkloopHtml "$controlPrefix/status/cc-runner?projectRoot=$projectArg&pair=$pairArg")'>查看 CC 输出</button>")
    [void]$cards.AppendLine("<button type='button' data-open-url='$(Encode-WorkloopHtml "$controlPrefix/status/codex-plan?projectRoot=$projectArg&pair=$pairArg")'>查看 Codex 规划</button>")
    [void]$cards.AppendLine("<button type='button' data-open-url='$(Encode-WorkloopHtml "$controlPrefix/status/summary?projectRoot=$projectArg&pair=$pairArg")'>查看总结生成</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$pairPathArg")'>打开 Pair</button>")
    if (Test-Path -LiteralPath $row.ReportPath) { [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$reportPathArg")'>打开报告</button>") }
    if (Test-Path -LiteralPath $row.ReplyPath) { [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$replyPathArg")'>打开裁决</button>") }
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$projectPathArg")'>打开项目</button>")
    if (Test-Path -LiteralPath $row.HistoryDir) { [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/open?path=$historyPathArg")'>打开 History</button>") }
    [void]$cards.AppendLine("</div></section>")
    [void]$cards.AppendLine("<section class='action-group'><h4>绑定</h4><div class='actions'>")
    [void]$cards.AppendLine("<button type='button' data-rebind-codex='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/rebind-codex?projectRoot=$projectArg&pair=$pairArg")'>绑定/重绑 Codex</button>")
    [void]$cards.AppendLine("<button type='button' data-rebind-cc='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/rebind-cc?projectRoot=$projectArg&pair=$pairArg")'>绑定/重绑 CC</button>")
    [void]$cards.AppendLine("</div></section>")
    [void]$cards.AppendLine("<section class='action-group'><h4>总结 / 审计</h4><div class='actions'>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/export?projectRoot=$projectArg&pair=$pairArg")'>生成审计</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/review?projectRoot=$projectArg&pair=$pairArg")'>生成复盘</button>")
    [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='将调用 Claude Code 重新分析当前项目和 pair 数据，可能消耗 Claude Code 额度。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=cc&force=1")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/summary?projectRoot=$projectArg&pair=$pairArg")'>重新生成总结（CC）</button>")
    [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='将调用 Codex read-only 重新分析当前项目和 pair 数据，可能消耗 Codex 额度。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=codex&force=1")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/summary?projectRoot=$projectArg&pair=$pairArg")'>重新生成总结（Codex）</button>")
    [void]$cards.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=local&force=1")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/summary?projectRoot=$projectArg&pair=$pairArg")'>重新生成本地摘要</button>")
    [void]$cards.AppendLine("</div></section>")
    [void]$cards.AppendLine("<section class='action-group danger-zone'><h4>归档</h4><div class='actions'>")
    [void]$cards.AppendLine("<button type='button' class='danger-action' data-confirm='归档 Pair 会把目录移动到 .ai-relay/archived-pairs，不会删除数据。确认归档？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/archive-pair?projectRoot=$projectArg&pair=$pairArg")' data-refresh='true'>归档 Pair</button>")
    [void]$cards.AppendLine("</div></section>")
    [void]$cards.AppendLine("</div></details>")
  }
  [void]$cards.AppendLine("<section class='health-box'><h3>处理提示：$(Encode-WorkloopHtml $row.HealthLabel)</h3>")
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
$actionStates = @('failed','blocked_user','report_ready','reply_unread','inbox_unread','summary_stale')
$runningStates = @('running')
$completedStates = @('completed')
$actionCount = @($rows | Where-Object { $_.PrimaryState -in $actionStates }).Count
$runningCount = @($rows | Where-Object { $_.PrimaryState -in $runningStates }).Count
$completedCount = @($rows | Where-Object { $_.PrimaryState -in $completedStates }).Count
$watchCount = @($rows | Where-Object { $_.Priority -gt 70 -and $_.HealthLevel -eq 'watch' }).Count
[void]$summary.AppendLine("<div class='summary-item action'><strong>$actionCount</strong><span>需要处理</span></div>")
[void]$summary.AppendLine("<div class='summary-item running'><strong>$runningCount</strong><span>正在运行</span></div>")
[void]$summary.AppendLine("<div class='summary-item done'><strong>$completedCount</strong><span>最近完成 / 可归档</span></div>")
[void]$summary.AppendLine("<div class='summary-item watch'><strong>$watchCount</strong><span>需要关注</span></div>")

$attentionRows = @($sortedRows | Where-Object { $_.PrimaryState -in $actionStates -or $_.HealthLevel -eq 'action' })
$attentionPayload = @($attentionRows | Select-Object -First 8 | ForEach-Object {
  [pscustomobject]@{
    pairId = [string]$_.PairId
    projectName = [string]$_.ProjectName
    label = [string]$_.PrimaryLabel
    action = [string]$_.PrimaryAction
    detail = [string]$_.PrimaryDetail
  }
})
$attentionJson = if ($attentionPayload.Count -gt 0) { ConvertTo-Json -InputObject $attentionPayload -Compress -Depth 4 } else { '[]' }
$attentionBanner = ''
if ($attentionRows.Count -gt 0) {
  $attentionItems = ($attentionRows | Select-Object -First 4 | ForEach-Object {
    "<li><strong>$(Encode-WorkloopHtml $_.PairId)</strong><span>$(Encode-WorkloopHtml $_.PrimaryLabel)</span><em>$(Encode-WorkloopHtml $_.PrimaryAction)</em></li>"
  }) -join "`n"
  $moreText = if ($attentionRows.Count -gt 4) { "<p class='attention-more'>还有 $($attentionRows.Count - 4) 个 pair 需要处理。</p>" } else { '' }
  $attentionBanner = @"
    <section class="attention-banner" aria-live="polite">
      <div>
        <h2>需要你处理</h2>
        <p>这些 pair 卡在需要点击、裁决、续跑、送审或查看失败原因的状态。优先处理这里，再看其他卡片。</p>
      </div>
      <ul>$attentionItems</ul>
      $moreText
      <button type="button" id="enable-workloop-notifications">开启桌面通知</button>
      <span id="workloop-notification-hint" class="notification-hint"></span>
    </section>
"@
}

function Add-DashboardBoardSection {
  param(
    [System.Text.StringBuilder]$Builder,
    [string]$Title,
    [object[]]$Rows,
    [string]$EmptyText,
    [string]$SectionClass = ''
  )
  if ($Rows.Count -gt 0) {
    [void]$Builder.AppendLine("<section class='action-board $SectionClass'><div class='section-head'><h2>$(Encode-WorkloopHtml $Title)</h2><span>$($Rows.Count)</span></div>")
  } else {
    [void]$Builder.AppendLine("<section class='action-board empty-board $SectionClass'><div class='section-head'><h2>$(Encode-WorkloopHtml $Title)</h2><span>0</span></div><p>$(Encode-WorkloopHtml $EmptyText)</p></section>")
    return
  }
  foreach ($row in $Rows) {
    $projectArg = Encode-WorkloopUrl $row.ProjectRoot
    $pairArg = Encode-WorkloopUrl $row.PairId
    [void]$Builder.AppendLine("<article class='action-row state-$([regex]::Replace($row.PrimaryState, '[^A-Za-z0-9_-]', '-'))'>")
    [void]$Builder.AppendLine("<div class='action-pair'><strong>$(Encode-WorkloopHtml $row.PairId)</strong><span>$(Encode-WorkloopHtml $row.ProjectName)</span></div>")
    [void]$Builder.AppendLine("<div class='action-status'><b>$(Encode-WorkloopHtml $row.PrimaryLabel)</b><span>$(Encode-WorkloopHtml $row.PrimaryDetail)</span></div>")
    [void]$Builder.AppendLine("<p class='action-summary'>$(Encode-WorkloopHtml $row.FocusText)</p>")
    if ($controlPrefix) {
      [void]$Builder.AppendLine("<div class='actions compact-actions'>")
      if ($row.PrimaryState -in @('running','failed')) {
        $runningStatusUrl = if ($row.WorkloopRunnerActive) { "$controlPrefix/status/workloop?projectRoot=$projectArg&pair=$pairArg" } else { "$controlPrefix/status/cc-runner?projectRoot=$projectArg&pair=$pairArg" }
        [void]$Builder.AppendLine("<button type='button' data-open-url='$(Encode-WorkloopHtml $runningStatusUrl)'>$(Encode-WorkloopHtml $row.PrimaryAction)</button>")
      } elseif ($row.PrimaryState -eq 'summary_stale') {
        [void]$Builder.AppendLine("<button type='button' class='danger-action' data-confirm='将调用 Claude Code 重新分析当前项目和 pair 数据，可能消耗 Claude Code 额度。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=cc&force=1")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/summary?projectRoot=$projectArg&pair=$pairArg")'>$(Encode-WorkloopHtml $row.PrimaryAction)</button>")
      } elseif ($row.PrimaryState -eq 'blocked_user') {
        $primaryStatusUrl = "$controlPrefix/status/workloop?projectRoot=$projectArg&pair=$pairArg"
        [void]$Builder.AppendLine("<button type='button' class='danger-action' data-resume-goal='true' data-project='$(Encode-WorkloopHtml $row.ProjectRoot)' data-pair='$(Encode-WorkloopHtml $row.PairId)' data-goal='$(Encode-WorkloopHtml $row.Goal)' data-round='$(Encode-WorkloopHtml $row.Round)' data-max-rounds='$(Encode-WorkloopHtml $row.MaxRounds)' data-url='$(Encode-WorkloopHtml "$controlPrefix/action/resume-goal?projectRoot=$projectArg&pair=$pairArg")' data-status-url='$(Encode-WorkloopHtml $primaryStatusUrl)'>续同一 Pair</button>")
      } elseif ($row.PrimaryState -in @('report_ready','reply_unread','inbox_unread','goal_ready')) {
        $primaryStatusUrl = "$controlPrefix/status/workloop?projectRoot=$projectArg&pair=$pairArg"
        [void]$Builder.AppendLine("<button type='button' class='danger-action' data-confirm='按状态机开始/继续：可能让 Codex 规划、送 Codex 审核，或调用 Claude CLI 执行任务。确认继续？' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/continue-goal?projectRoot=$projectArg&pair=$pairArg")' data-status-url='$(Encode-WorkloopHtml $primaryStatusUrl)'>$(Encode-WorkloopHtml $row.PrimaryAction)</button>")
      } elseif ($row.PrimaryState -eq 'completed') {
        $summaryAnalyzer = if ([string]::IsNullOrWhiteSpace($row.SummaryAnalyzer)) { 'cc' } else { [string]$row.SummaryAnalyzer }
        [void]$Builder.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=$summaryAnalyzer&cache=1")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/summary?projectRoot=$projectArg&pair=$pairArg")'>查看总结</button>")
      }
      if ($row.PrimaryState -ne 'completed') {
        $summaryButtonText = if ($row.SummaryState -in @('missing','stale')) { '生成 / 更新总结' } else { '查看总结' }
        $summaryAnalyzer = if ([string]::IsNullOrWhiteSpace($row.SummaryAnalyzer)) { 'cc' } else { [string]$row.SummaryAnalyzer }
        [void]$Builder.AppendLine("<button type='button' data-post='$(Encode-WorkloopHtml "$controlPrefix/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=$summaryAnalyzer&cache=1")' data-status-url='$(Encode-WorkloopHtml "$controlPrefix/status/summary?projectRoot=$projectArg&pair=$pairArg")'>$(Encode-WorkloopHtml $summaryButtonText)</button>")
      }
      [void]$Builder.AppendLine("</div>")
    }
    [void]$Builder.AppendLine("</article>")
  }
  [void]$Builder.AppendLine("</section>")
}

$actionBoard = [System.Text.StringBuilder]::new()
$actionRows = @($sortedRows | Where-Object { $_.PrimaryState -in $actionStates } | Select-Object -First 8)
$runningRows = @($sortedRows | Where-Object { $_.PrimaryState -in $runningStates } | Select-Object -First 6)
$completedRows = @($sortedRows | Where-Object { $_.PrimaryState -in $completedStates } | Select-Object -First 6)
Add-DashboardBoardSection -Builder $actionBoard -Title '需要你处理' -Rows $actionRows -EmptyText '当前没有必须介入的 pair。' -SectionClass 'board-action'
Add-DashboardBoardSection -Builder $actionBoard -Title '正在运行' -Rows $runningRows -EmptyText '当前没有正在执行的 pair。' -SectionClass 'board-running'
Add-DashboardBoardSection -Builder $actionBoard -Title '最近完成 / 可归档' -Rows $completedRows -EmptyText '当前没有标记为完成的 pair。' -SectionClass 'board-done'

if ($rows.Count -eq 0) {
  [void]$cards.AppendLine("<section class='empty'>没有找到任何 .ai-relay/pairs。请传入包含 workloop 数据的项目目录。</section>")
}

$projectList = ($resolvedProjects | ForEach-Object { "<li><code>$(Encode-WorkloopHtml $_)</code></li>" }) -join "`n"
$systemPanel = ''
if ($controlPrefix) {
  $systemPanel = @"
    <section class="system-panel">
      <h2>系统状态</h2>
      <p>查看本机 Workloop / Claude / Codex / MCP 相关进程，必要时只清理孤儿 MCP 候选。</p>
      <div class="actions"><button type="button" data-open-url="$(Encode-WorkloopHtml "$controlPrefix/status/processes")">进程诊断 / 清理残留</button></div>
    </section>
"@
}
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
        <label class="session-scope-label">
          <span>会话范围</span>
          <span class="checkbox-line"><input type="checkbox" id="session-show-all-projects"> 高级：显示全部项目会话</span>
        </label>
        <label>Pair ID（英文）
          <input id="create-pair-id" name="pair" required pattern="[A-Za-z0-9][A-Za-z0-9._-]*" title="只能使用英文字母、数字、点、下划线、短横线，并且必须以字母或数字开头。" placeholder="例如 knowledge_skeleton">
          <span class="field-hint">这是目录名和命令参数，只能用英文/数字/._-；中文目标请写到右侧目标框。</span>
        </label>
        <label>目标（可中文）
          <input name="task" placeholder="例如：知识库骨架是什么东西，情况怎么样">
        </label>
        <label class="session-picker-label">Codex 会话
          <input id="codex-session-search" placeholder="搜索 title / sessionId / cwd">
          <select id="codex-session-select" size="6">
            <option value="">None - 创建新 Codex 会话</option>
          </select>
          <input type="hidden" id="codex-session-id-field" name="codexSessionId" value="">
          <div id="codex-session-detail" class="session-detail">正在扫描本机 Codex sessions...</div>
          <details class="advanced-field">
            <summary>Advanced 手动输入</summary>
            <input id="codex-session-manual" placeholder="手动输入 Codex Session ID">
          </details>
        </label>
        <label class="session-picker-label">Claude Code 会话
          <input id="cc-session-search" placeholder="搜索已有 pair 的 CC session">
          <select id="cc-session-select" size="4">
            <option value="">None - 执行时打开新的 Claude Code 终端</option>
          </select>
          <input type="hidden" id="cc-session-id-field" name="ccSessionId" value="">
          <div id="cc-session-detail" class="session-detail">正在读取已有 pair 的 CC session...</div>
          <details class="advanced-field">
            <summary>Advanced 手动输入</summary>
            <input id="cc-session-manual" placeholder="手动输入 Claude Code Session ID">
          </details>
        </label>
        <button type="submit">创建 Pair</button>
      </form>
      <p>扫描会按 .git 和常见工程清单识别项目根；默认只显示所选项目的 Codex / Claude Code 会话；勾选高级选项才显示全部项目会话。Codex 选 None 会新建会话并绑定；CC 选 None 会在执行时打开新的 Claude Code 原生终端。</p>
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
    .attention-banner { display:grid; grid-template-columns:minmax(220px,1fr) minmax(300px,1.4fr) auto; gap:14px; align-items:center; margin:0 0 22px; background:linear-gradient(135deg,#fffdf8,#fff6e8); border:1px solid #e4c58d; border-left:6px solid var(--warn); border-radius:8px; padding:16px; box-shadow:0 10px 24px rgba(91,57,13,.08); }
    .attention-banner h2 { margin:0 0 6px; font-size:18px; }
    .attention-banner p { margin:0; color:#65410d; font-size:13px; line-height:1.5; }
    .attention-banner ul { margin:0; padding:0; list-style:none; display:grid; gap:8px; }
    .attention-banner li { display:grid; grid-template-columns:minmax(130px,1fr) auto auto; gap:8px; align-items:center; font-size:13px; }
    .attention-banner li span { color:#7a4a00; }
    .attention-banner li em { font-style:normal; border:1px solid #d6b07b; border-radius:999px; padding:2px 8px; background:#fff; color:#7a4a00; white-space:nowrap; }
    .attention-banner button { border:1px solid var(--warn); border-radius:6px; background:#fff; color:#7a4a00; padding:8px 12px; font:inherit; cursor:pointer; }
    .attention-banner button[hidden] { display:none; }
    .attention-more, .notification-hint { color:#7a4a00; font-size:12px; }
    .action-board { margin:0 0 22px; background:#fff; border:1px solid var(--line); border-radius:8px; padding:16px; }
    .section-head { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:12px; }
    .section-head h2 { margin:0; font-size:18px; }
    .section-head span { min-width:30px; text-align:center; border:1px solid var(--line); border-radius:999px; padding:3px 8px; color:var(--muted); }
    .action-row { display:grid; grid-template-columns:minmax(160px,220px) minmax(160px,220px) minmax(320px,1fr) auto; gap:14px; align-items:start; border-top:1px solid var(--line); padding:12px 0; }
    .action-row:first-of-type { border-top:0; padding-top:0; }
    .action-pair strong { display:block; font-size:15px; }
    .action-pair span, .muted { color:var(--muted); font-size:12px; }
    .action-status b { display:block; font-size:13px; margin-bottom:4px; }
    .action-status span { display:block; color:var(--muted); font-size:12px; line-height:1.45; }
    .action-summary { margin:0; font-size:13px; line-height:1.5; overflow-wrap:anywhere; display:-webkit-box; -webkit-line-clamp:3; -webkit-box-orient:vertical; overflow:hidden; }
    .empty-board p { margin:0; color:var(--muted); }
    .projects { margin:0 0 22px; padding:14px 18px; background:#fff; border:1px solid var(--line); border-radius:8px; }
    .projects h2 { font-size:15px; margin:0 0 10px; }
    .projects ul { margin:0; padding-left:18px; color:var(--muted); }
    .system-panel { margin:0 0 22px; padding:14px 18px; background:#fff; border:1px solid var(--line); border-radius:8px; }
    .system-panel h2 { font-size:15px; margin:0 0 8px; }
    .system-panel p { margin:0; color:var(--muted); font-size:13px; }
    .create-panel { margin:0 0 22px; padding:14px 18px; background:#fff; border:1px solid var(--line); border-radius:8px; }
    .create-panel h2 { font-size:15px; margin:0 0 12px; }
    .create-panel form { display:grid; grid-template-columns:minmax(220px,1fr) minmax(170px,220px) minmax(160px,220px) minmax(220px,1fr) minmax(280px,1.2fr) minmax(280px,1.2fr) auto; gap:10px; align-items:end; margin-top:10px; }
    .create-panel label { display:grid; gap:5px; color:var(--muted); font-size:12px; }
    .create-panel input, .create-panel select { border:1px solid var(--line); border-radius:6px; padding:8px 10px; font:inherit; color:var(--ink); background:#fff; min-width:0; }
    .field-hint { color:var(--muted); font-size:11px; line-height:1.35; }
    .field-error { color:var(--danger); font-size:12px; font-weight:600; }
    .create-panel button { border:1px solid var(--accent); border-radius:6px; background:#e7f2ed; color:var(--accent); padding:8px 12px; font:inherit; cursor:pointer; }
    .create-panel p { margin:10px 0 0; color:var(--muted); font-size:12px; }
    .session-scope-label { align-self:end; }
    .checkbox-line { display:flex; align-items:center; gap:6px; min-height:38px; color:var(--ink); border:1px solid var(--line); border-radius:6px; padding:8px 10px; background:#fff; }
    .checkbox-line input { width:auto; min-width:0; padding:0; }
    .session-picker-label { align-self:stretch; }
    .session-picker-label select { min-height:142px; padding:4px; font-size:12px; }
    .session-detail { min-height:64px; border:1px solid var(--line); border-radius:6px; background:#fbfcfa; color:var(--muted); padding:8px; font-size:12px; line-height:1.45; overflow-wrap:anywhere; }
    .advanced-field { color:var(--muted); font-size:12px; }
    .advanced-field summary { cursor:pointer; margin-bottom:5px; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(min(100%,520px),1fr)); gap:16px; align-items:start; }
    .pair-card { background:var(--card); border:1px solid var(--line); border-left:5px solid var(--muted); border-radius:8px; padding:16px; }
    .pair-card.needs-attention { background:linear-gradient(180deg,#fff,#fffdfa); border-color:#e4d2ad; box-shadow:0 12px 28px rgba(91,57,13,.09); }
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
    .needs-attention .badge { border-color:#d6b07b; background:#fff6e7; color:#7a4a00; font-weight:600; }
    .attention-callout { display:grid; gap:4px; border:1px solid #ead5a9; border-radius:8px; background:#fff9ef; padding:10px 12px; margin:-2px 0 12px; }
    .attention-callout strong { color:#7a4a00; font-size:13px; }
    .attention-callout span { color:#65410d; font-size:13px; line-height:1.45; }
    .attention-callout em { color:#176b5d; font-style:normal; font-weight:600; font-size:13px; }
    .pair-focus { border:1px solid var(--line); border-radius:8px; background:#fbfcfa; padding:12px; margin-bottom:12px; }
    .pair-focus dl { display:grid; gap:10px; margin:0; }
    .pair-focus dd { display:-webkit-box; -webkit-line-clamp:4; -webkit-box-orient:vertical; overflow:hidden; }
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
    .auto-run-error { margin:6px 0 0; color:var(--danger); font-size:12px; }
    .primary-actions { margin:10px 0 12px; }
    .actions .main-action { border-color:var(--accent); background:#e7f2ed; color:var(--accent); font-weight:600; }
    .needs-attention .actions .main-action { border-color:#b87516; background:#fff2dc; color:#7a4a00; box-shadow:0 0 0 3px rgba(184,117,22,.10); }
    .compact-actions { margin:0; justify-content:flex-end; min-width:190px; max-width:230px; }
    .debug-actions { border-top:1px solid var(--line); margin-top:10px; padding-top:10px; width:100%; }
    .debug-actions summary { cursor:pointer; color:var(--muted); font-size:12px; }
    .debug-actions .actions { margin:10px 0 0; }
    .action-groups { display:grid; gap:12px; margin-top:12px; }
    .action-group { border-top:1px solid var(--line); padding-top:10px; }
    .action-group:first-child { border-top:0; padding-top:0; }
    .action-group h4 { margin:0 0 8px; font-size:12px; color:var(--muted); font-weight:600; }
    .action-group .actions { margin:0; }
    .danger-zone h4 { color:var(--danger); }
    .binding-box { border-top:1px solid var(--line); margin-top:10px; padding-top:10px; }
    .binding-box h3 { margin:0 0 8px; font-size:13px; color:var(--muted); }
    .missing { color:var(--danger); font-weight:600; }
    .ok-text { color:var(--accent); font-weight:600; }
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
      .attention-banner { grid-template-columns:1fr; }
      .attention-banner li { grid-template-columns:1fr; }
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
    $attentionBanner
    $($actionBoard.ToString())
    <section class="projects">
      <h2>扫描项目</h2>
      <ul>$projectList</ul>
    </section>
    $systemPanel
    $createPanel
    <section class="grid">
      $($cards.ToString())
    </section>
  </main>
  <footer>提示：创建 Pair 后，把 bind-request 交给对应 Codex 会话完成绑定。</footer>
  <script>
    const workloopAttentionItems = $attentionJson;
    function setupWorkloopAttentionNotifications() {
      const items = Array.isArray(workloopAttentionItems) ? workloopAttentionItems : [];
      const enableButton = document.getElementById('enable-workloop-notifications');
      const hint = document.getElementById('workloop-notification-hint');
      if (!items.length) {
        if (enableButton) enableButton.hidden = true;
        return;
      }
      const attentionKey = items.map((item) => [item.projectName, item.pairId, item.label, item.action].join('|')).join('||');
      const storageKey = 'ai-workloop-attention-notified';
      const cooldownMs = 10 * 60 * 1000;
      function shouldNotify() {
        try {
          const last = JSON.parse(localStorage.getItem(storageKey) || '{}');
          return last.key !== attentionKey || !last.at || (Date.now() - Number(last.at)) > cooldownMs;
        } catch {
          return true;
        }
      }
      function markNotified() {
        try {
          localStorage.setItem(storageKey, JSON.stringify({ key: attentionKey, at: Date.now() }));
        } catch {}
      }
      function notifyNow() {
        if (!('Notification' in window) || Notification.permission !== 'granted' || !shouldNotify()) return;
        const first = items[0];
        const more = items.length > 1 ? '，还有 ' + (items.length - 1) + ' 个 pair' : '';
        new Notification('Agent Workloop 需要处理', {
          body: first.pairId + '：' + first.label + '，建议：' + first.action + more,
          tag: 'agent-workloop-attention'
        });
        markNotified();
      }
      if (!('Notification' in window)) {
        if (enableButton) enableButton.hidden = true;
        if (hint) hint.textContent = '当前浏览器不支持桌面通知。';
        return;
      }
      if (Notification.permission === 'granted') {
        if (enableButton) enableButton.hidden = true;
        notifyNow();
      } else if (Notification.permission === 'denied') {
        if (enableButton) enableButton.hidden = true;
        if (hint) hint.textContent = '浏览器已禁用通知；仍可按顶部“需要你处理”区域操作。';
      } else if (enableButton) {
        enableButton.hidden = false;
        if (hint) hint.textContent = '首次需要手动允许浏览器通知。';
        enableButton.addEventListener('click', async () => {
          const permission = await Notification.requestPermission();
          if (permission === 'granted') {
            enableButton.hidden = true;
            if (hint) hint.textContent = '已开启。以后有需要介入的 pair 会弹出桌面通知。';
            notifyNow();
          } else if (hint) {
            hint.textContent = '未开启通知；顶部提醒仍会显示。';
          }
        });
      }
    }
    setupWorkloopAttentionNotifications();
    document.querySelectorAll('button[data-open-url]').forEach((button) => {
      button.addEventListener('click', () => {
        const url = button.getAttribute('data-open-url');
        if (url) window.open(url, '_blank');
      });
    });
    async function postWorkloopAction(url) {
      const response = await fetch(url, { method: 'POST' });
      if (!response.ok) {
        const text = await response.text();
        throw new Error(text.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() || ('HTTP ' + response.status));
      }
      return response;
    }
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
          const response = await postWorkloopAction(url);
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
    document.querySelectorAll('button[data-auto-continue="true"]').forEach((button) => {
      const url = button.getAttribute('data-post');
      const statusUrl = button.getAttribute('data-status-url');
      const key = 'ai-workloop-auto:' + (button.getAttribute('data-auto-key') || url || '');
      if (!url || sessionStorage.getItem(key)) return;
      sessionStorage.setItem(key, new Date().toISOString());
      button.textContent = '自动续跑中...';
      button.disabled = true;
      postWorkloopAction(url)
        .then(() => {
          if (statusUrl) {
            setTimeout(() => { window.location.href = statusUrl; }, 700);
          } else {
            setTimeout(() => { window.location.reload(); }, 700);
          }
        })
        .catch((error) => {
          button.textContent = '自动续跑失败';
          button.disabled = false;
          const hint = document.createElement('p');
          hint.className = 'auto-run-error';
          hint.textContent = '自动续跑失败：' + error.message;
          button.insertAdjacentElement('afterend', hint);
        });
    });
    function formatSessionTime(value) {
      if (!value) return '';
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return value;
      return date.toLocaleString();
    }
    function optionLabel(text, maxLength) {
      const value = (text || '').replace(/\s+/g, ' ').trim();
      if (!value) return '';
      return value.length > maxLength ? value.slice(0, maxLength - 1) + '…' : value;
    }
    function escapeHtml(text) {
      return String(text || '').replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
    }
    function setupSessionPicker(config) {
      const select = document.getElementById(config.selectId);
      const search = document.getElementById(config.searchId);
      const hidden = document.getElementById(config.hiddenId);
      const detail = document.getElementById(config.detailId);
      const manual = document.getElementById(config.manualId);
      const projectSelect = document.querySelector('#create-pair-form select[name="projectRoot"]');
      const showAllProjects = document.getElementById('session-show-all-projects');
      if (!select || !search || !hidden || !detail) return;
      let sessions = [];
      const noneDetail = config.noneDetail;
      function normalizePath(value) {
        return String(value || '').replace(/\//g, '\\').replace(/\\+$/g, '').toLowerCase();
      }
      function sessionProjectText(session) {
        return normalizePath(config.projectText(session));
      }
      function wantedProject() {
        if (showAllProjects && showAllProjects.checked) return '';
        return normalizePath(projectSelect ? projectSelect.value : '');
      }
      function matchesProject(session) {
        const wanted = wantedProject();
        if (!wanted) return true;
        const value = sessionProjectText(session);
        return value === wanted || value.startsWith(wanted + '\\') || wanted.startsWith(value + '\\');
      }
      function setDetail(session) {
        if (!session) {
          detail.textContent = noneDetail;
          return;
        }
        detail.innerHTML = config.renderDetail(session);
      }
      function render() {
        const query = (search.value || '').toLowerCase().trim();
        const selected = select.value;
        select.innerHTML = '';
        const noneOption = document.createElement('option');
        noneOption.value = '';
        noneOption.textContent = config.noneLabel;
        select.appendChild(noneOption);
        sessions
          .filter((session) => {
            if (!matchesProject(session)) return false;
            if (!query) return true;
            return config.searchText(session).toLowerCase().includes(query);
          })
          .slice(0, 100)
          .forEach((session) => {
            const option = document.createElement('option');
            option.value = config.value(session);
            option.textContent = config.label(session);
            select.appendChild(option);
          });
        select.value = Array.from(select.options).some((option) => option.value === selected) ? selected : '';
        const active = sessions.find((session) => config.value(session) === select.value);
        setDetail(active);
        hidden.value = select.value || '';
      }
      select.addEventListener('change', () => {
        const active = sessions.find((session) => config.value(session) === select.value);
        hidden.value = select.value || '';
        if (manual) manual.value = '';
        setDetail(active);
      });
      search.addEventListener('input', render);
      if (projectSelect) projectSelect.addEventListener('change', render);
      if (showAllProjects) showAllProjects.addEventListener('change', render);
      if (manual) {
        manual.addEventListener('input', () => {
          hidden.value = manual.value.trim();
          if (hidden.value) {
            detail.textContent = '使用 Advanced 手动输入：' + hidden.value;
          } else {
            const active = sessions.find((session) => config.value(session) === select.value);
            hidden.value = select.value || '';
            setDetail(active);
          }
        });
      }
      fetch(config.url)
        .then((response) => response.json())
        .then((data) => {
          sessions = Array.isArray(data.sessions) ? data.sessions : [];
          render();
          if (sessions.length === 0) {
            detail.textContent = data.error || config.emptyDetail;
          }
        })
        .catch((error) => {
          detail.textContent = '扫描失败：' + error;
        });
    }
    setupSessionPicker({
      url: '/api/dev/relay-sessions/codex',
      selectId: 'codex-session-select',
      searchId: 'codex-session-search',
      hiddenId: 'codex-session-id-field',
      detailId: 'codex-session-detail',
      manualId: 'codex-session-manual',
      noneLabel: 'None - 创建新 Codex 会话',
      noneDetail: 'None：创建 Pair 时自动新建 Codex 会话并绑定。',
      emptyDetail: '没有扫描到 Codex session。选择 None 会自动新建。',
      value: (session) => session.id || '',
      label: (session) => optionLabel((session.bound ? '[已绑定' + (session.boundPairCount ? '×' + session.boundPairCount : '') + '] ' : '') + (session.title || session.id) + ' · ' + (session.cwd || '') + ' · ' + formatSessionTime(session.lastWriteAt) + ' · ' + (session.sizeLabel || session.size || ''), 140),
      projectText: (session) => session.cwd || '',
      searchText: (session) => [session.title, session.id, session.cwd, session.source, session.originator].filter(Boolean).join(' '),
      renderDetail: (session) => [
        '<strong>' + escapeHtml(optionLabel(session.title || session.id, 160)) + '</strong>',
        'sessionId: <code>' + escapeHtml(session.id || '') + '</code>',
        '绑定状态: ' + (session.bound ? '<span class="missing">已绑定到 ' + escapeHtml((session.boundPairs || []).map((item) => item.pairId + ' @ ' + (item.projectRoot || '')).join('；')) + '</span>' : '<span class="ok-text">未绑定</span>'),
        'cwd: ' + escapeHtml(session.cwd || '-'),
        'lastWriteAt: ' + escapeHtml(formatSessionTime(session.lastWriteAt)),
        'file size: ' + escapeHtml(session.sizeLabel || session.size || '-'),
        'path: ' + escapeHtml(session.path || '-')
      ].join('<br>')
    });
    setupSessionPicker({
      url: '/api/dev/relay-sessions/cc',
      selectId: 'cc-session-select',
      searchId: 'cc-session-search',
      hiddenId: 'cc-session-id-field',
      detailId: 'cc-session-detail',
      manualId: 'cc-session-manual',
      noneLabel: 'None - 执行时打开新的 Claude Code 终端',
      noneDetail: 'None：不预绑定 CC session，执行时打开新的 Claude Code 原生终端。',
      emptyDetail: '没有扫描到 Claude Code 项目会话。选择 None 会在执行时打开新的 Claude Code 原生终端。',
      value: (session) => session.id || session.name || '',
      label: (session) => optionLabel((session.bound ? '[已绑定' + (session.boundPairCount ? '×' + session.boundPairCount : '') + '] ' : '') + (session.title || session.id || session.name) + ' · ' + (session.cwd || session.projectRoot || '') + ' · ' + (session.gitBranch || '') + ' · ' + (session.sizeLabel || ''), 140),
      projectText: (session) => session.cwd || session.projectRoot || '',
      searchText: (session) => [session.title, session.id, session.name, session.pairId, session.projectRoot, session.cwd, session.gitBranch].filter(Boolean).join(' '),
      renderDetail: (session) => [
        '<strong>' + escapeHtml(optionLabel(session.title || session.id || session.name, 120)) + '</strong>',
        'sessionId: <code>' + escapeHtml(session.id || '-') + '</code>',
        'sessionName: ' + escapeHtml(session.name || '-'),
        '绑定状态: ' + (session.bound ? '<span class="missing">已绑定到 ' + escapeHtml((session.boundPairs || []).map((item) => item.pairId + ' @ ' + (item.projectRoot || '')).join('；')) + '</span>' : '<span class="ok-text">未绑定</span>'),
        'cwd: ' + escapeHtml(session.cwd || session.projectRoot || '-'),
        'branch: ' + escapeHtml(session.gitBranch || '-'),
        'lastWriteAt: ' + escapeHtml(formatSessionTime(session.lastWriteAt)),
        'file size: ' + escapeHtml(session.sizeLabel || session.size || '-'),
        'path: ' + escapeHtml(session.path || '-')
      ].join('<br>')
    });
    const createForm = document.getElementById('create-pair-form');
    if (createForm) {
      createForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const pairInput = createForm.querySelector('input[name="pair"]');
        const pairValue = pairInput ? pairInput.value.trim() : '';
        const oldError = createForm.querySelector('.pair-id-error');
        if (oldError) oldError.remove();
        if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(pairValue)) {
          if (pairInput) {
            const error = document.createElement('span');
            error.className = 'field-error pair-id-error';
            error.textContent = 'Pair ID 只能用英文、数字、点、下划线或短横线，并且必须以字母或数字开头。中文请写到“目标”。例如：knowledge_skeleton';
            pairInput.insertAdjacentElement('afterend', error);
            pairInput.focus();
          }
          return;
        }
        const resultWindow = window.open('', '_blank');
        if (resultWindow) {
          resultWindow.document.open();
          resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>正在创建 Pair</title><style>body{font-family:Segoe UI,system-ui,sans-serif;margin:24px;color:#1f2933;background:#f7f7f4}main{max-width:980px;margin:0 auto;background:#fff;border:1px solid #d8ddd8;border-radius:8px;padding:18px}h1{margin-top:0;font-size:22px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f5f6f2;border:1px solid #e4e6df;border-radius:6px;padding:12px}</style></head><body><main><h1>正在创建 Pair</h1><pre>已提交创建请求。\\n如果 Codex 会话选择 None，系统会创建新的 Codex session 并完成绑定，可能需要几十秒到几分钟。\\n请不要重复点击创建按钮，等待这个页面返回结果。</pre></main></body></html>');
          resultWindow.document.close();
        }
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
            if (response.ok && window.opener === null) {
              setTimeout(() => window.location.reload(), 800);
            }
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
        const maxRoundsRaw = window.prompt('最大轮次：', '10');
        if (maxRoundsRaw === null) return;
        const resultWindow = window.open('', '_blank');
        const statusUrl = '/status/codex-plan?projectRoot=' + encodeURIComponent(projectRoot) + '&pair=' + encodeURIComponent(pair);
        if (resultWindow) {
          resultWindow.document.open();
          resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>正在启动 Codex 规划</title><style>body{font-family:Segoe UI,system-ui,sans-serif;margin:24px;color:#1f2933;background:#f7f7f4}main{max-width:980px;margin:0 auto;background:#fff;border:1px solid #d8ddd8;border-radius:8px;padding:18px}h1{margin-top:0;font-size:22px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f5f6f2;border:1px solid #e4e6df;border-radius:6px;padding:12px}a{color:#176b5d}</style></head><body><main><h1>正在启动 Codex 规划</h1><pre>请求已发送。系统会打开一个 Codex planner 前台终端，并把结果自动写入 cc-inbox.md。\\n如果这个页面没有自动更新，可以打开状态页查看。</pre><p><a href="' + statusUrl.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '">打开 Codex 规划状态页</a></p></main></body></html>');
          resultWindow.document.close();
        }
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
    document.querySelectorAll('button[data-resume-goal]').forEach((button) => {
      button.addEventListener('click', async () => {
        const pair = button.getAttribute('data-pair') || '';
        const projectRoot = button.getAttribute('data-project') || '';
        const url = button.getAttribute('data-url') || '';
        const statusUrl = button.getAttribute('data-status-url') || ('/status/workloop?projectRoot=' + encodeURIComponent(projectRoot) + '&pair=' + encodeURIComponent(pair));
        const currentGoal = button.getAttribute('data-goal') || '';
        const currentRound = parseInt(button.getAttribute('data-round') || '0', 10) || 0;
        const currentMax = parseInt(button.getAttribute('data-max-rounds') || '10', 10) || 10;
        const defaultGoal = currentGoal
          ? currentGoal + '\\n\\n续跑要求：先复核当前 git 状态、最新 cc-report/codex-reply 和总结；不要重复执行已完成事项；只处理剩余最小任务。'
          : '在同一个 pair 中继续收口：先复核当前状态，不要重复执行已完成事项，只处理剩余最小任务。';
        const goal = window.prompt('输入续跑目标。会保留当前 pair、Codex/CC session 和历史：', defaultGoal);
        if (goal === null) return;
        const defaultMax = String(Math.max(currentMax + 5, currentRound + 5));
        const maxRoundsRaw = window.prompt('新的总最大轮次（必须大于当前轮次 ' + currentRound + '）：', defaultMax);
        if (maxRoundsRaw === null) return;
        const resultWindow = window.open('', '_blank');
        if (resultWindow) {
          resultWindow.document.open();
          resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>正在续跑 Pair</title><style>body{font-family:Segoe UI,system-ui,sans-serif;margin:24px;color:#1f2933;background:#f7f7f4}main{max-width:980px;margin:0 auto;background:#fff;border:1px solid #d8ddd8;border-radius:8px;padding:18px}h1{margin-top:0;font-size:22px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f5f6f2;border:1px solid #e4e6df;border-radius:6px;padding:12px}a{color:#176b5d}</style></head><body><main><h1>正在续跑同一个 Pair</h1><pre>请求已发送。系统会保留 pair 历史和 session，只刷新 goal.json 并启动 Workloop 状态机。\\n旧的 codex-reply / cc-inbox 会被标记为已读，避免重复执行过期指令。</pre><p><a href="' + statusUrl.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '">打开 Workloop 状态页</a></p></main></body></html>');
          resultWindow.document.close();
        }
        const data = new URLSearchParams();
        data.set('projectRoot', projectRoot);
        data.set('pair', pair);
        data.set('goal', goal);
        data.set('maxRounds', maxRoundsRaw);
        const oldText = button.textContent;
        button.textContent = '续跑中...';
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
          const errorText = '续跑失败：' + error;
          if (resultWindow) {
            resultWindow.document.open();
            resultWindow.document.write('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>续跑失败</title></head><body><pre>' + errorText.replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])) + '</pre></body></html>');
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
        const ccSessionId = window.prompt('输入 Claude Code Session ID；留空表示不预绑定，执行时打开新的 Claude Code 原生终端。', '');
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

