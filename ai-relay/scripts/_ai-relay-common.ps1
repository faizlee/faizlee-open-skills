function Get-AiRelayProjectRoot {
  (Get-Location).ProviderPath
}

function Get-AiRelayRoot {
  param([string]$ProjectRoot)
  Join-Path $ProjectRoot '.ai-relay'
}

function Assert-AiRelayPairName {
  param([Parameter(Mandatory=$true)][string]$Pair)
  if ($Pair -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Pair ID 无效：'$Pair'。Pair ID 是目录名和命令参数，只能使用英文字母、数字、点、下划线或短横线，并且必须以字母或数字开头。中文说明请写到目标字段。例如：knowledge_skeleton。"
  }
}

function Get-AiRelayPairId {
  param([string]$ProjectRoot, [string]$Pair)
  if ($Pair) { return $Pair }
  $currentPath = Join-Path (Get-AiRelayRoot $ProjectRoot) 'current-pair.json'
  if (-not (Test-Path -LiteralPath $currentPath)) {
    throw "No current pair. Run /bind <pair> or ai-relay-use.ps1 -Pair <pair> first."
  }
  $current = Get-Content -LiteralPath $currentPath -Raw -Encoding utf8 | ConvertFrom-Json
  if (-not $current.pairId) {
    throw "current-pair.json does not contain pairId. Run ai-relay-use.ps1 -Pair <pair>."
  }
  $current.pairId
}

function Get-AiRelayPairDir {
  param([string]$ProjectRoot, [string]$Pair)
  Join-Path (Join-Path (Get-AiRelayRoot $ProjectRoot) 'pairs') $Pair
}

function Read-AiRelayPairJson {
  param([string]$PairDir)
  $pairJsonPath = Join-Path $PairDir 'pair.json'
  if (-not (Test-Path -LiteralPath $pairJsonPath)) {
    throw "pair.json not found: $pairJsonPath. Bind this pair from Codex first."
  }
  Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
}

function Write-AiRelayJson {
  param([Parameter(Mandatory=$true)]$Object, [Parameter(Mandatory=$true)][string]$Path)
  $Object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Set-AiRelayCurrentPair {
  param([string]$ProjectRoot, [string]$Pair, [string]$Task)
  $root = Get-AiRelayRoot $ProjectRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    task = $Task
    projectRoot = $ProjectRoot
    updatedAt = (Get-Date).ToString('o')
  }) (Join-Path $root 'current-pair.json')
}

function Add-AiRelayLog {
  param([string]$PairDir, [string]$Event, [string]$Detail)
  $logPath = Join-Path $PairDir 'relay-log.md'
  $entry = @"

## $(Get-Date -Format o) - $Event
$Detail
"@
  Add-Content -LiteralPath $logPath -Value $entry -Encoding utf8
}

function Copy-AiRelayText {
  param([string]$Text)
  try {
    Set-Clipboard -Value $Text
    return $true
  } catch {
    Write-Warning "Failed to copy to clipboard: $($_.Exception.Message)"
    return $false
  }
}

function Read-AiRelayTextFile {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    return (Get-Content -LiteralPath $Path -Raw -Encoding utf8)
  }
  ''
}

function Get-AiRelayStructuredJsonFromText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

  $candidates = New-Object System.Collections.Generic.List[string]
  foreach ($match in [regex]::Matches($Text, '(?ms)```(?:json)?\s*(\{.*?\})\s*```')) {
    $candidates.Add($match.Groups[1].Value.Trim())
  }
  foreach ($match in [regex]::Matches($Text, '(?ms)(\{\s*"workloopDecision"\s*:.*?\})')) {
    $candidates.Add($match.Groups[1].Value.Trim())
  }

  foreach ($candidate in $candidates) {
    try {
      $json = $candidate | ConvertFrom-Json
      if ($json -and ($json.PSObject.Properties.Name -contains 'workloopDecision')) {
        return $json
      }
    } catch {
    }
  }
  return $null
}

function Get-AiRelayWorkloopDecision {
  param(
    [string]$Text,
    [string]$FallbackText = ''
  )

  $json = Get-AiRelayStructuredJsonFromText -Text $Text
  if ($json) {
    $decision = if ($json.workloopDecision) { ([string]$json.workloopDecision).Trim().ToLowerInvariant() } else { '' }
    if ($decision -notin @('continue','completed','needs_user','blocked')) {
      $decision = 'needs_user'
    }
    $nextTask = if ($json.nextTask) { [string]$json.nextTask } else { '' }
    $reason = if ($json.reason) { [string]$json.reason } else { 'Codex returned structured Workloop decision.' }
    $shouldWriteInbox = $false
    if ($json.PSObject.Properties.Name -contains 'shouldWriteInbox') {
      $shouldWriteInbox = [System.Convert]::ToBoolean($json.shouldWriteInbox)
    } elseif ($decision -eq 'continue') {
      $shouldWriteInbox = $true
    }
    if ($decision -ne 'continue') { $shouldWriteInbox = $false }
    if ($decision -eq 'continue' -and [string]::IsNullOrWhiteSpace($nextTask)) {
      $decision = 'needs_user'
      $shouldWriteInbox = $false
      $reason = 'Structured decision requested continue but nextTask was empty.'
    }
    return [pscustomobject]@{
      Decision = $decision
      ShouldWriteInbox = $shouldWriteInbox
      Reason = $reason
      NextTask = $nextTask
      Source = 'structured'
    }
  }

  $fallback = if ([string]::IsNullOrWhiteSpace($FallbackText)) { $Text } else { $FallbackText }
  $normalized = ($fallback -replace '\s+', ' ').Trim()
  $terminalSignal = $normalized -match '无下一轮|无需下一轮|不需要下一轮|没有下一轮|不需要继续|无需继续|无需操作|无需执行|目标已完成|当前目标已完成|本目标已完成|本 pair 已完成|pair 已完成|停止|结束|关闭当前\s*pair|归档|等待用户|保持.*结束|不要再运行|不要继续'
  if ($terminalSignal) {
    return [pscustomobject]@{
      Decision = 'completed'
      ShouldWriteInbox = $false
      Reason = 'Fallback regex found a clear terminal signal.'
      NextTask = $fallback
      Source = 'fallback_regex_completed'
    }
  }

  $needsUserSignal = $normalized -match '人工裁决|需要用户|用户确认|无法判断|冲突风险|blocked|阻塞'
  if ($needsUserSignal) {
    return [pscustomobject]@{
      Decision = 'needs_user'
      ShouldWriteInbox = $false
      Reason = 'Fallback regex found a user-decision or blocked signal.'
      NextTask = $fallback
      Source = 'fallback_regex_needs_user'
    }
  }

  return [pscustomobject]@{
    Decision = 'needs_user'
    ShouldWriteInbox = $false
    Reason = 'Missing structured Workloop decision; conservative fallback stopped instead of continuing.'
    NextTask = $fallback
    Source = 'fallback_missing_structured'
  }
}

function Encode-AiRelayHtml {
  param([string]$Text)
  [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function ConvertTo-AiRelayFileUri {
  param(
    [string]$ProjectRoot,
    [string]$Path
  )
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  $normalized = $Path.Trim() -replace '/', '\'
  $candidates = New-Object System.Collections.Generic.List[string]
  if ([System.IO.Path]::IsPathRooted($normalized)) {
    $candidates.Add($normalized)
  } else {
    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
      $candidates.Add((Join-Path $ProjectRoot $normalized))
      $candidates.Add((Join-Path (Join-Path $ProjectRoot 'docs\project') $normalized))
      $candidates.Add((Join-Path (Join-Path $ProjectRoot 'docs') $normalized))
      $candidates.Add((Join-Path (Join-Path $ProjectRoot '.ai-relay') $normalized))
    }
    $candidates.Add($normalized)
  }
  foreach ($candidate in $candidates) {
    if (-not (Test-Path -LiteralPath $candidate)) { continue }
    try {
      return ([System.Uri]::new((Resolve-Path -LiteralPath $candidate -ErrorAction Stop).ProviderPath)).AbsoluteUri
    } catch {
    }
  }
  return ''
}

function Test-AiRelayProcessAlive {
  param([string]$ProcessId)
  if ($ProcessId -notmatch '^\d+$') { return $false }
  return [bool](Get-Process -Id ([int]$ProcessId) -ErrorAction SilentlyContinue)
}

function Get-AiRelayStatusInsight {
  param(
    [string]$Kind = 'runner',
    [string]$Status = 'unknown',
    [bool]$ProcessAlive = $false,
    [string]$Message = '',
    [string]$ResultStatus = '',
    [bool]$HasOutput = $false,
    [bool]$HasStderr = $false,
    [bool]$HasReport = $false,
    [bool]$HasReply = $false,
    [bool]$HasInbox = $false
  )

  $statusText = if ([string]::IsNullOrWhiteSpace($Status)) { 'unknown' } else { $Status }
  $kindLabel = switch ($Kind) {
    'cc' { 'Claude Code 执行' }
    'codex-plan' { 'Codex 规划' }
    'workloop' { 'Workloop 状态机' }
    'summary' { '总结生成' }
    default { 'runner' }
  }

  $label = '状态未知'
  $detail = if ($Message) { $Message } else { '还没有足够信息判断当前状态。' }
  $next = '查看输出、stdout/stderr 或手动刷新。'
  $tone = 'unknown'
  $needsUser = $false

  if ($statusText -in @('queued','started','running')) {
    $label = "$kindLabel 正在运行"
    $detail = if ($ProcessAlive) { "$kindLabel 进程仍在运行。" } else { "$kindLabel 状态显示正在运行，但当前没有检测到对应进程。" }
    $next = if ($ProcessAlive) { '继续等待，状态页会自动刷新；需要中断时使用停止按钮。' } else { '查看输出和最新文件时间；如果结果文件已更新，可返回 Dashboard 继续下一步，否则重新执行。' }
    $tone = if ($ProcessAlive) { 'running' } else { 'warn' }
    $needsUser = -not $ProcessAlive
  } elseif ($statusText -eq 'stale') {
    $label = "$kindLabel 状态过期"
    $detail = '状态文件停在 running，但进程已经不存在。'
    $next = '优先查看输出、stderr、报告/裁决文件更新时间；确认完成后继续流程，否则重新执行。'
    $tone = 'warn'
    $needsUser = $true
  } elseif ($statusText -eq 'failed') {
    $label = "$kindLabel 失败"
    $detail = if ($HasStderr) { 'stderr 或输出中有错误信息。' } else { '没有 stderr 时，通常需要看 runner 输出或最新报告判断失败点。' }
    $next = '先读错误片段，修复原因后再重新执行。'
    $tone = 'bad'
    $needsUser = $true
  } elseif ($statusText -eq 'completed') {
    $label = "$kindLabel 已完成"
    $detail = 'runner 进程已结束。'
    $next = '查看结果文件；如果结果可用就返回 Dashboard 继续下一步或归档。'
    $tone = 'good'
  } elseif ($statusText -eq 'unknown') {
    $label = "$kindLabel 尚无状态"
    $detail = '还没有写入状态文件，或状态文件无法解析。'
    $next = '从 Dashboard 重新执行，或打开 Pair 目录检查生成文件。'
    $tone = 'warn'
    $needsUser = $true
  }

  if ($Kind -eq 'summary' -and $ResultStatus) {
    switch ($ResultStatus) {
      'running' {
        $label = '总结正在生成'
        $detail = '总结 runner 正在检查缓存、调用分析器或生成 HTML。'
        $next = '等待自动刷新。'
        $tone = 'running'
      }
      'cache_miss' {
        $label = '总结缓存未命中'
        $detail = '这次只是检查缓存，没有生成新总结。'
        $next = '点击重新生成总结；需要省额度时先用本地摘要。'
        $tone = 'warn'
        $needsUser = $true
      }
      'stale_artifact' {
        $label = '总结模板过期'
        $detail = '已有总结不是当前 HTML artifact 版本。'
        $next = '重新生成新版总结。'
        $tone = 'warn'
        $needsUser = $true
      }
      'stale_summary' {
        $label = '总结内容过期'
        $detail = 'pair 数据已变化，已有总结不再代表当前状态。'
        $next = '重新生成总结。'
        $tone = 'warn'
        $needsUser = $true
      }
      'generated' {
        $label = '总结已生成'
        $detail = '本次已生成新的总结。'
        $next = '打开 HTML 总结阅读。'
        $tone = 'good'
      }
      'cache_hit' {
        $label = '总结缓存命中'
        $detail = '已有总结与当前 pair 数据匹配。'
        $next = '直接打开 HTML 总结。'
        $tone = 'good'
      }
      'failed' {
        $label = '总结生成失败'
        $detail = '总结 runner 执行失败。'
        $next = '查看 stderr 和 runner 输出。'
        $tone = 'bad'
        $needsUser = $true
      }
    }
  }

  if ($Kind -eq 'workloop' -and $HasReport -and -not $HasReply) {
    $next = '当前最可能的下一步是送 Codex 裁决。'
  } elseif ($Kind -eq 'workloop' -and $HasReply) {
    $next = '当前最可能的下一步是让 Claude Code 执行 Codex 裁决。'
  } elseif ($Kind -eq 'cc' -and $HasReport) {
    $next = 'CC 已写入报告；返回 Dashboard 执行 /workloop 送审。'
  } elseif ($Kind -eq 'cc' -and $HasInbox) {
    $next = 'CC 正在处理或应处理 cc-inbox.md 中的任务。'
  }

  [pscustomobject]@{
    Label = $label
    Detail = $detail
    NextAction = $next
    Tone = $tone
    NeedsUser = $needsUser
  }
}
