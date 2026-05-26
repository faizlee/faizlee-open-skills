param(
  [string]$Pair,
  [int]$Last = 0,
  [ValidateSet('cc','codex','local')][string]$Analyzer = 'cc',
  [ValidateSet('md','html','both')][string]$Format = 'both',
  [string]$OutDir,
  [switch]$UseCache,
  [switch]$CacheOnly,
  [switch]$RenderOnly,
  [switch]$Open
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

function Read-WorkloopFile {
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

function Get-CompactText {
  param([string]$Text, [int]$MaxLength = 420)
  $clean = ($Text -replace "`r", '' -replace '\n{3,}', "`n`n").Trim()
  if ($clean.Length -le $MaxLength) { return $clean }
  return $clean.Substring(0, $MaxLength) + '...'
}

function Get-CompactLine {
  param([string]$Text, [int]$MaxLength = 160)
  $clean = ($Text -replace "`r", ' ' -replace "`n", ' ' -replace '\s+', ' ').Trim()
  if ($clean.Length -le $MaxLength) { return $clean }
  return $clean.Substring(0, $MaxLength) + '...'
}

function Get-Decision {
  param([string]$Reply)
  if ($Reply -match '不接受') { return '不接受' }
  if ($Reply -match '部分接受') { return '部分接受' }
  if ($Reply -match '接受') { return '接受' }
  return '无法判断'
}

function Test-ReworkNeeded {
  param([string]$Reply)
  if ($Reply -match '不需要继续返工|不需要返工|不需要') { return $false }
  if ($Reply -match '需要返工|返工原因|证据不足|补证据|不接受') { return $true }
  return $false
}

function Get-SectionText {
  param([string]$Text, [string]$Heading)
  if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
  $escaped = [regex]::Escape($Heading)
  $match = [regex]::Match($Text, "(?ms)^##\s+$escaped\s*\r?\n(?<body>.*?)(?=^##\s+|\z)")
  if ($match.Success) { return $match.Groups['body'].Value.Trim() }
  return ''
}

function Get-CodexNextInstruction {
  param([string]$Reply)
  $match = [regex]::Match($Reply, '(?ms)^##\s*4[.、]\s*给 Claude Code 的下一轮指令\s*\r?\n(?<body>.*?)(?=^##\s*5[.、]|\z)')
  if ($match.Success) { return $match.Groups['body'].Value.Trim() }
  return ''
}

function Get-KeywordSet {
  param([string]$Text)
  $items = New-Object System.Collections.Generic.List[string]
  foreach ($m in [regex]::Matches($Text, '[A-Za-z0-9_\-]{3,}|[\p{IsCJKUnifiedIdeographs}]{2,}')) {
    $value = $m.Value.Trim().ToLowerInvariant()
    if ($value.Length -ge 2 -and -not $items.Contains($value)) { $items.Add($value) }
    if ($value -match '^[\p{IsCJKUnifiedIdeographs}]+$' -and $value.Length -gt 2) {
      for ($i = 0; $i -le ($value.Length - 2); $i++) {
        $gram = $value.Substring($i, 2)
        if (-not $items.Contains($gram)) { $items.Add($gram) }
      }
      if ($value.Length -gt 3) {
        for ($i = 0; $i -le ($value.Length - 3); $i++) {
          $gram = $value.Substring($i, 3)
          if (-not $items.Contains($gram)) { $items.Add($gram) }
        }
      }
    }
  }
  return $items
}

function Get-OverlapCount {
  param([System.Collections.Generic.List[string]]$Needles, [string]$Haystack)
  if (-not $Needles -or [string]::IsNullOrWhiteSpace($Haystack)) { return 0 }
  $lower = $Haystack.ToLowerInvariant()
  $count = 0
  foreach ($item in $Needles) {
    if ($lower.Contains($item)) { $count++ }
  }
  return $count
}

function Get-SummaryTone {
  param([string]$Text)
  if ($Text -match '未发现|无明显|暂不需要|正常') { return 'good' }
  if ($Text -match '不接受|失败|低效|偏移|返工|缺少|无法|空转|风险|bug') { return 'bad' }
  if ($Text -match '完成|接受|正常|未发现') { return 'good' }
  if ($Text -match '部分|可能|需要|未知|判断') { return 'warn' }
  return 'neutral'
}

function Convert-InlineMarkdownToHtml {
  param([string]$Text)
  $html = Encode-Html $Text
  $html = [regex]::Replace($html, '`([^`]+)`', '<code>$1</code>')
  $html = [regex]::Replace($html, '\*\*(.+?)\*\*', '<strong>$1</strong>')
  return $html
}

function Convert-TimelineTextToHtml {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
  $html = Convert-InlineMarkdownToHtml $Text
  return ($html -replace "(`r`n|`n|`r)", '<br>')
}

function Test-MarkdownTableSeparator {
  param([string]$Line)
  if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
  $cells = @($Line.Trim().Trim('|') -split '\|')
  if ($cells.Count -lt 2) { return $false }
  foreach ($cell in $cells) {
    if ($cell.Trim() -notmatch '^:?-{3,}:?$') { return $false }
  }
  return $true
}

function Convert-MarkdownTableToHtml {
  param([string[]]$Rows)
  if (-not $Rows -or $Rows.Count -lt 2) { return '' }
  $header = @($Rows[0].Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
  $bodyRows = @()
  if ($Rows.Count -gt 2) { $bodyRows = @($Rows | Select-Object -Skip 2) }
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine('<div class="table-wrap"><table>')
  [void]$builder.AppendLine('<thead><tr>')
  foreach ($cell in $header) {
    [void]$builder.AppendLine("<th>$(Convert-InlineMarkdownToHtml $cell)</th>")
  }
  [void]$builder.AppendLine('</tr></thead>')
  [void]$builder.AppendLine('<tbody>')
  foreach ($row in $bodyRows) {
    if ([string]::IsNullOrWhiteSpace($row)) { continue }
    $cells = @($row.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
    [void]$builder.AppendLine('<tr>')
    foreach ($cell in $cells) {
      [void]$builder.AppendLine("<td>$(Convert-InlineMarkdownToHtml $cell)</td>")
    }
    [void]$builder.AppendLine('</tr>')
  }
  [void]$builder.AppendLine('</tbody></table></div>')
  return $builder.ToString()
}

function Convert-SimpleMarkdownToHtml {
  param([string]$Markdown)
  if ([string]::IsNullOrWhiteSpace($Markdown)) { return '<p class="muted">暂无内容。</p>' }
  $builder = [System.Text.StringBuilder]::new()
  $inList = $false
  $inCode = $false
  $code = [System.Text.StringBuilder]::new()
  $lines = @($Markdown -replace "`r", '' -split "`n")
  for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
    $rawLine = $lines[$lineIndex]
    $line = [string]$rawLine
    if ($line -match '^\s*````|^\s*```') {
      if ($inCode) {
        [void]$builder.AppendLine("<pre>$([System.Net.WebUtility]::HtmlEncode($code.ToString().TrimEnd()))</pre>")
        [void]$code.Clear()
        $inCode = $false
      } else {
        if ($inList) { [void]$builder.AppendLine('</ul>'); $inList = $false }
        $inCode = $true
      }
      continue
    }
    if ($inCode) {
      [void]$code.AppendLine($line)
      continue
    }
    if ([string]::IsNullOrWhiteSpace($line)) {
      if ($inList) { [void]$builder.AppendLine('</ul>'); $inList = $false }
      continue
    }
    if ($line.Trim().StartsWith('|') -and ($lineIndex + 1) -lt $lines.Count -and (Test-MarkdownTableSeparator $lines[$lineIndex + 1])) {
      if ($inList) { [void]$builder.AppendLine('</ul>'); $inList = $false }
      $tableRows = New-Object System.Collections.Generic.List[string]
      $tableRows.Add($line)
      $lineIndex++
      $tableRows.Add([string]$lines[$lineIndex])
      while (($lineIndex + 1) -lt $lines.Count -and ([string]$lines[$lineIndex + 1]).Trim().StartsWith('|')) {
        $lineIndex++
        $tableRows.Add([string]$lines[$lineIndex])
      }
      [void]$builder.AppendLine((Convert-MarkdownTableToHtml $tableRows.ToArray()))
      continue
    }
    if ($line -match '^###\s+(.+)$') {
      if ($inList) { [void]$builder.AppendLine('</ul>'); $inList = $false }
      [void]$builder.AppendLine("<h3>$(Convert-InlineMarkdownToHtml $Matches[1])</h3>")
      continue
    }
    if ($line -match '^##\s+(.+)$') {
      if ($inList) { [void]$builder.AppendLine('</ul>'); $inList = $false }
      [void]$builder.AppendLine("<h2>$(Convert-InlineMarkdownToHtml $Matches[1])</h2>")
      continue
    }
    if ($line -match '^#\s+(.+)$') {
      if ($inList) { [void]$builder.AppendLine('</ul>'); $inList = $false }
      [void]$builder.AppendLine("<h1>$(Convert-InlineMarkdownToHtml $Matches[1])</h1>")
      continue
    }
    if ($line -match '^\s*[-*]\s+(.+)$') {
      if (-not $inList) { [void]$builder.AppendLine('<ul>'); $inList = $true }
      [void]$builder.AppendLine("<li>$(Convert-InlineMarkdownToHtml $Matches[1])</li>")
      continue
    }
    if ($inList) { [void]$builder.AppendLine('</ul>'); $inList = $false }
    [void]$builder.AppendLine("<p>$(Convert-InlineMarkdownToHtml $line)</p>")
  }
  if ($inCode) {
    [void]$builder.AppendLine("<pre>$([System.Net.WebUtility]::HtmlEncode($code.ToString().TrimEnd()))</pre>")
  }
  if ($inList) { [void]$builder.AppendLine('</ul>') }
  return $builder.ToString()
}

function Convert-AgentNextSectionsForTerminalPair {
  param(
    [string]$Markdown,
    [string]$AuthoritativeTitle
  )

  if ([string]::IsNullOrWhiteSpace($Markdown)) { return $Markdown }

  $lines = @($Markdown -replace "`r", '' -split "`n")
  $builder = [System.Text.StringBuilder]::new()
  foreach ($rawLine in $lines) {
    $line = [string]$rawLine
    if ($line -match '^##\s+(\d+\.\s*)?(下一步推进指令|下一步推进建议|下一步建议|给 Claude Code 的下一轮指令)\s*$') {
      [void]$builder.AppendLine('## 可选后续建议（非当前 pair 自动执行）')
      continue
    }
    if ($line -match '^###\s*(可直接复制的目标指令|目标指令|下一步指令)\s*$') {
      [void]$builder.AppendLine('### 可选新目标候选')
      continue
    }
    if ($line -match '^\s*-\s*建议动作[：:]\s*(.+)$') {
      [void]$builder.AppendLine("- 可选动作候选: $($Matches[1])")
      continue
    }
    [void]$builder.AppendLine($line)
  }

  $note = @"
## 当前下一步以系统判定为准

当前 pair 已进入终态，权威下一步是：$AuthoritativeTitle。下面 AI 摘要里的后续建议只作为新目标候选，不代表当前 pair 应继续执行。

"@
  return "$note$($builder.ToString().TrimStart())"
}

function New-SummaryListHtml {
  param($Items, [string]$EmptyText)
  if (-not $Items -or @($Items).Count -eq 0) {
    return "<p class=""muted"">$(Encode-Html $EmptyText)</p>"
  }
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine('<ul class="compact-list">')
  foreach ($item in $Items) {
    [void]$builder.AppendLine("<li>$(Convert-InlineMarkdownToHtml ([string]$item))</li>")
  }
  [void]$builder.AppendLine('</ul>')
  return $builder.ToString()
}

function Convert-PathToFileUri {
  param([string]$ProjectRoot, [string]$Path)
  ConvertTo-AiRelayFileUri -ProjectRoot $ProjectRoot -Path $Path
}

function Get-EvidenceSnippets {
  param([string]$Text, [string[]]$Terms, [int]$Limit = 8)
  $items = New-Object System.Collections.Generic.List[object]
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  $lines = @($Text -replace "`r", '' -split "`n")
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = [string]$lines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    foreach ($term in $Terms) {
      if ([string]::IsNullOrWhiteSpace($term)) { continue }
      if ($line.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $start = [math]::Max(0, $i - 1)
        $end = [math]::Min($lines.Count - 1, $i + 1)
        $snippet = (($lines[$start..$end]) -join "`n").Trim()
        if ($snippet.Length -gt 520) { $snippet = $snippet.Substring(0, 520) + '...' }
        $items.Add([pscustomobject]@{
          Term = $term
          Line = $i + 1
          Text = $snippet
        })
        break
      }
    }
    if ($items.Count -ge $Limit) { break }
  }
  return @($items.ToArray())
}

function New-KnowledgePyramidSvgHtml {
  param([string]$AllText)
  $isKnowledgePyramid = $AllText -match 'knowledge pyramid|知识金字塔|L0-L7|North Star|Governance'
  if (-not $isKnowledgePyramid) {
    return '<p class="muted">当前 pair 没有识别到 L0-L7 / Knowledge Pyramid 结构，暂不生成专用结构图。</p>'
  }
  $hasSchema = $AllText -match 'schema|Schema|concept-registry\.schema\.json'
  $hasConceptData = $AllText -match 'concept 实例|concepts|concept-registry\.json'
  $hasEmptySignal = $AllText -match '空壳|无实际概念数据|实例无|concept 实例无'
  $hasDomainBlocker = $AllText -match 'domain 待裁决|待定 domain|待裁决 domain|credits|payment'
  $hasWorkflowIntegration = $AllText -match 'CLAUDE\.md|工作流引用|工作流集成'

  $schemaClass = if ($hasSchema) { 'ok' } else { 'warn' }
  $conceptClass = if ($hasEmptySignal -or -not $hasConceptData) { 'bad' } else { 'ok' }
  $domainClass = if ($hasDomainBlocker) { 'warn' } else { 'ok' }
  $workflowClass = if ($hasWorkflowIntegration -and -not ($AllText -match '未被 CLAUDE\.md|未被.*工作流')) { 'ok' } else { 'warn' }

  @"
<div class="pyramid-wrap">
  <svg viewBox="0 0 760 430" role="img" aria-label="Knowledge Pyramid L0 到 L7 状态图">
    <defs>
      <linearGradient id="pyramidFill" x1="0" x2="0" y1="0" y2="1">
        <stop offset="0" stop-color="#e8f4ee"/>
        <stop offset="1" stop-color="#fff7e6"/>
      </linearGradient>
    </defs>
    <rect x="1" y="1" width="758" height="428" rx="12" fill="#fbfcfa" stroke="#d9ded7"/>
    <text x="36" y="42" class="svg-title">Knowledge Pyramid 当前形态</text>
    <text x="36" y="68" class="svg-subtitle">把线性报告转成空间结构：层级、阻塞点、下一步一眼可见。</text>
    <g transform="translate(78,94)">
      <polygon points="250,0 500,294 0,294" fill="url(#pyramidFill)" stroke="#b9c7bb" stroke-width="2"/>
      <line x1="51" y1="234" x2="449" y2="234" class="svg-line"/>
      <line x1="85" y1="194" x2="415" y2="194" class="svg-line"/>
      <line x1="119" y1="154" x2="381" y2="154" class="svg-line"/>
      <line x1="153" y1="114" x2="347" y2="114" class="svg-line"/>
      <line x1="187" y1="74" x2="313" y2="74" class="svg-line"/>
      <line x1="221" y1="34" x2="279" y2="34" class="svg-line"/>
      <text x="250" y="24" text-anchor="middle" class="layer">L0 North Star</text>
      <text x="250" y="63" text-anchor="middle" class="layer">L1 Domain</text>
      <text x="250" y="103" text-anchor="middle" class="layer">L2 Capability</text>
      <text x="250" y="143" text-anchor="middle" class="layer">L3 Workflow</text>
      <text x="250" y="183" text-anchor="middle" class="layer">L4 Contract</text>
      <text x="250" y="223" text-anchor="middle" class="layer">L5 Implementation</text>
      <text x="250" y="263" text-anchor="middle" class="layer">L6 Verification</text>
      <text x="250" y="291" text-anchor="middle" class="layer">L7 Governance</text>
    </g>
    <g transform="translate(520,112)">
      <rect class="status $schemaClass" x="0" y="0" width="190" height="52" rx="8"/>
      <text x="14" y="23" class="status-title">Schema</text>
      <text x="14" y="40" class="status-text">$(if ($hasSchema) { '已有定义' } else { '未识别' })</text>
      <rect class="status $conceptClass" x="0" y="68" width="190" height="52" rx="8"/>
      <text x="14" y="91" class="status-title">Concept 实例</text>
      <text x="14" y="108" class="status-text">$(if ($hasEmptySignal -or -not $hasConceptData) { '空壳 / 待填充' } else { '已识别数据' })</text>
      <rect class="status $domainClass" x="0" y="136" width="190" height="52" rx="8"/>
      <text x="14" y="159" class="status-title">Domain 决策</text>
      <text x="14" y="176" class="status-text">$(if ($hasDomainBlocker) { '有待裁决项' } else { '未见阻塞' })</text>
      <rect class="status $workflowClass" x="0" y="204" width="190" height="52" rx="8"/>
      <text x="14" y="227" class="status-title">工作流集成</text>
      <text x="14" y="244" class="status-text">$(if ($workflowClass -eq 'ok') { '已有集成信号' } else { '需确认接入' })</text>
    </g>
  </svg>
</div>
"@
}

function ConvertTo-WorkloopPairSlug {
  param([string]$Text, [string]$Fallback = 'next_pair')
  $slug = ([string]$Text).Trim().ToLowerInvariant()
  $slug = $slug -replace '[^a-z0-9_.-]+', '_'
  $slug = $slug.Trim('._-')
  if ([string]::IsNullOrWhiteSpace($slug)) { $slug = $Fallback }
  if ($slug -notmatch '^[a-z0-9]') { $slug = "pair_$slug" }
  if ($slug.Length -gt 48) { $slug = $slug.Substring(0, 48).Trim('._-') }
  return $slug
}

function Get-FirstMeaningfulLine {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
  foreach ($line in @($Text -replace "`r", '' -split "`n")) {
    $clean = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { continue }
    if ($clean -match '^[-*#|`\s]+$') { continue }
    return ($clean -replace '^[-*]\s+', '').Trim()
  }
  return ''
}

function New-WorkloopSummaryState {
  param(
    [string]$GoalStatus,
    [string]$GoalText,
    [object]$LatestRound,
    [int]$RoundCount,
    [int]$PartialCount,
    [int]$RejectCount,
    [int]$ReworkCount,
    [int]$VerificationCount,
    [int]$RawIdleTailCount,
    [int]$DriftWarningCount
  )

  $hasIdleLoop = ($RawIdleTailCount -ge 2)
  $idleTailCount = if ($hasIdleLoop) { $RawIdleTailCount } else { 0 }

  $overall = '无法判断'
  if ($GoalStatus -eq 'completed' -and $hasIdleLoop) {
    $overall = '目标已完成，但历史轮次存在空转'
  } elseif ($GoalStatus -eq 'completed') {
    $overall = '目标已完成'
  } elseif ($GoalStatus -eq 'stopped') {
    $overall = '目标已停止，需要人工判断'
  } elseif ($hasIdleLoop) {
    $overall = '目标可能已完成，但 Workloop 出现空转'
  } elseif ($LatestRound -and $LatestRound.Decision -eq '接受' -and -not $LatestRound.NextInstruction) {
    $overall = '最近一轮已接受，可能已完成'
  } elseif ($LatestRound -and $LatestRound.Decision -eq '接受' -and $LatestRound.NextInstruction) {
    $overall = '本轮已接受，存在下一轮任务'
  } elseif ($LatestRound -and $LatestRound.Decision -eq '部分接受') {
    $overall = '部分完成，仍有后续任务或验证缺口'
  } elseif ($LatestRound -and $LatestRound.Decision -eq '不接受') {
    $overall = '未通过，需要返工'
  } elseif ($RoundCount -eq 0) {
    $overall = '还没有历史轮次'
  }

  $efficiency = '正常'
  if ($hasIdleLoop -and $GoalStatus -eq 'completed') {
    $efficiency = "历史空转（尾部 $idleTailCount 轮无新任务）"
  } elseif ($hasIdleLoop) {
    $efficiency = "严重空转（尾部 $idleTailCount 轮无新任务）"
  } elseif ($RoundCount -ge 5 -and ($PartialCount + $RejectCount) -ge [math]::Ceiling($RoundCount * 0.6)) {
    $efficiency = '可能低效循环'
  } elseif ($ReworkCount -ge 2) {
    $efficiency = '返工偏多'
  } elseif ($VerificationCount -eq 0 -and $RoundCount -gt 0) {
    $efficiency = '缺少验证证据'
  }

  $drift = '未发现明显偏移'
  if ($DriftWarningCount -gt 0) {
    $drift = '可能偏移'
  } elseif ([string]::IsNullOrWhiteSpace($GoalText)) {
    $drift = '没有明确目标，无法判断'
  }

  $needsUser = $true
  if ($overall -match '目标已完成|最近一轮已接受' -and $drift -eq '未发现明显偏移' -and $efficiency -eq '正常') {
    $needsUser = $false
  }

  $diagnosis = 'unknown'
  if ($GoalStatus -eq 'completed' -and $hasIdleLoop) { $diagnosis = 'completed_with_idle_history' }
  elseif ($GoalStatus -eq 'completed') { $diagnosis = 'completed' }
  elseif ($GoalStatus -eq 'stopped') { $diagnosis = 'stopped' }
  elseif ($hasIdleLoop) { $diagnosis = 'idle_loop' }
  elseif ($efficiency -match '低效|返工') { $diagnosis = 'inefficient' }
  elseif ($drift -eq '可能偏移') { $diagnosis = 'drift' }
  elseif ($RoundCount -eq 0) { $diagnosis = 'not_started' }
  elseif ($overall -eq '本轮已接受，存在下一轮任务') { $diagnosis = 'continue_next_round' }
  elseif ($overall -match '接受|完成') { $diagnosis = 'accepted' }

  return [pscustomobject]@{
    Diagnosis = $diagnosis
    Overall = $overall
    Efficiency = $efficiency
    Drift = $drift
    HasIdleLoop = $hasIdleLoop
    IdleTailCount = $idleTailCount
    NeedsUser = $needsUser
  }
}

function Get-WorkloopNextMove {
  param(
    [string]$PairId,
    [string]$ProjectRoot,
    [string]$GoalText,
    [string]$GoalStatus,
    [string]$Overall,
    [string]$Efficiency,
    [string]$Drift,
    [string]$LastNextInstruction,
    [string]$LatestRoundNextInstruction,
    [string]$Inbox,
    [string]$Report,
    [string]$Reply,
    [string]$LocalSummary
  )

  $allText = "$GoalText`n$Inbox`n$Report`n$Reply`n$LocalSummary"
  $latestNext = if (-not [string]::IsNullOrWhiteSpace($LastNextInstruction)) { $LastNextInstruction } else { $LatestRoundNextInstruction }
  $hasStopSignal = $latestNext -match '暂不执行|等待用户|用户确认|是否只向用户|本轮结束|不要继续|无需下一轮'
  $isAccepted = $Overall -match '完成|接受'
  $hasCurrentIdleLoop = $Efficiency -match '^严重空转'
  $hasIdleHistory = $Efficiency -match '^历史空转'
  $hasWorkloopStopBug = $hasCurrentIdleLoop -or (($GoalStatus -ne 'completed') -and ($allText -match '空转|终止 bug|终止逻辑|无需下一轮.*空转|循环到 maxRounds|反复.*无新任务|浪费.*额度'))
  $isKnowledgePyramid = $allText -match 'Knowledge Pyramid|知识金字塔|Project Knowledge Pyramid|L0-L7|concept-registry|concept registry|pilot concepts|pilot concept'
  $mentionsAiEditorial = $allText -match 'ai-editorial|AI Editorial|AI 编辑部|ai编辑部'
  $mentionsDomainDecision = $allText -match 'domain|credits-payment|payment|待裁决'

  if ($GoalStatus -eq 'completed' -and -not $hasCurrentIdleLoop -and -not $hasIdleHistory) {
    $goal = @"
当前 pair 已完成，不需要继续执行。

建议：
1. 不要再运行这个 pair，避免重复消耗额度。
2. 如需保留记录，生成或查看总结/审计后归档。
3. 如果发现新的验证缺口，用新 pair 承接新目标。
"@.Trim()
    return [pscustomobject]@{
      Action = 'close_pair'
      Title = '建议关闭或归档当前 pair'
      Detail = '当前 goal 已是 completed，且没有当前空转证据；继续执行没有收益。'
      SuggestedPairId = $PairId
      Goal = $goal
      CommandHint = ''
    }
  }

  if ($hasIdleHistory) {
    $goal = @"
目标：运行时验证 Agent Workloop 的 round 递增和 maxRounds 保护是否已经生效。

背景：
当前 pair 已完成，但历史轮次显示曾经发生尾部空转。不要继续运行这个旧 pair；需要用新的最小测试 pair 验证现在的终止保护。

边界：
1. 只操作 ai-relay 测试 pair，不修改业务代码。
2. 不修改生产 pair 的历史数据。
3. 不使用 subagent、codex-with-cc、--last。

任务：
1. 创建或选择一个 maxRounds=2 的测试 pair。
2. 观察每轮 goal.json 的 round 是否递增。
3. 验证达到 maxRounds 或 Codex 明确无需下一轮时，goal.json 是否进入 completed/stopped，且不再继续派发。
4. 输出压缩报告：最终 status、round、stopReason、是否仍会空转。
"@.Trim()
    return [pscustomobject]@{
      Action = 'open_new_pair'
      Title = '建议归档当前 pair，并用新 pair 验证终止保护'
      Detail = '当前 pair 已完成；空转是历史行为证据，后续应通过独立测试 pair 验证当前版本，而不是继续旧 pair。'
      SuggestedPairId = 'workloop_round_guard_test'
      Goal = $goal
      CommandHint = "/workloop workloop_round_guard_test $goal"
    }
  }

  if ($hasWorkloopStopBug) {
    $goal = @"
目标：修复 Agent Workloop 的空转终止逻辑，让已完成的 pair 自动停止，而不是继续循环到 maxRounds。

背景：
当前复盘发现 pair 已经被 Codex 接受并明确“无需下一轮指令”，但 Workloop 仍继续触发 CC/Codex 多轮空转，浪费额度并让面板状态误导用户。

边界：
1. 只修改 ai-relay / Agent Workloop 工具脚本和文档。
2. 不修改业务代码。
3. 不改变 Codex/Claude Code 的基础文件通信协议。
4. 不使用 subagent、不启动 codex-with-cc、不使用 --last。

任务：
1. 阅读 ai-workloop-runner.ps1、ai-relay-cc.ps1、ai-workloop-summary.ps1 中与 goal 状态、轮次、停止条件相关的逻辑。
2. 当 Codex 验收为接受/完成，且下一步包含“无需下一轮 / 不需要继续 / 停止 / 等待用户 / 保持结束”等收口信号时，将 goal.json 更新为 completed。
3. completed/stopped 状态必须优先于未读 report/reply/inbox，避免已完成 pair 又被送回 CC 执行。
4. 总结页必须把“严重空转 / 终止 bug / 系统性风险”显示到顶部指标和右侧推荐动作，不能被“最近接受”覆盖。
5. 验证：用一个历史空转 pair 生成总结，确认顶部显示需要介入，推荐动作指向修复 Workloop；并静态检查脚本不包含 --last、codex-with-cc、subagent 调用。
"@.Trim()
    return [pscustomobject]@{
      Action = 'open_new_pair'
      Title = '建议开新 pair 修复 Workloop 空转'
      Detail = '当前 pair 出现多轮无新任务或超过轮次仍继续的证据，应先修复终止逻辑。'
      SuggestedPairId = 'workloop_auto_stop'
      Goal = $goal
      CommandHint = "/workloop workloop_auto_stop $goal"
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($latestNext) -and -not $hasStopSignal) {
    $goal = $latestNext.Trim()
    return [pscustomobject]@{
      Action = 'continue_current_pair'
      Title = '建议当前 pair 继续执行 Codex 下一轮指令'
      Detail = 'Codex 已验收本轮报告，并给出了明确的下一轮可执行任务；不应开新 pair 或标记完成。'
      SuggestedPairId = $PairId
      Goal = $goal
      CommandHint = "/workloop $PairId $goal"
    }
  }

  if ($isKnowledgePyramid -and ($hasStopSignal -or $isAccepted -or $latestNext -match 'pilot|concept|domain|填充|裁决')) {
    $suggestedPair = if ($mentionsAiEditorial) { 'knowledge_pyramid_pilot' } else { ConvertTo-WorkloopPairSlug "$PairId`_pilot" 'knowledge_pyramid_pilot' }
    $domainLine = if ($mentionsAiEditorial) { '选择 ai-editorial 作为 pilot domain，填一条 L0-L7 完整链路。' } else { '选择一个最小 pilot domain，填一条 L0-L7 完整链路。' }
    $domainRisk = if ($mentionsDomainDecision) { '对 credits/payment 等待裁决项只记录风险，不展开实现。' } else { '对仍待裁决的 domain 只记录风险，不展开实现。' }
    $goal = @"
目标：继续完善 Project Knowledge Pyramid，让它从“文档骨架”变成“有一条真实 L0-L7 概念链路的数据样例”。

边界：
1. 只处理 docs/project/ 相关文件。
2. 不修改业务代码。
3. 不修改 CLAUDE.md，除非报告中只提出建议，不直接落地。
4. 不一次性填满所有 domain。
5. 不大范围重构文档结构。

任务：
1. 阅读 docs/project/readme.md、concept-model.md、concept-registry.schema.json、domains.md、systems-map.md、knowledge-hygiene.md。
2. 基于现有 schema 创建或完善 concept-registry.json。
3. $domainLine
4. 明确每个节点的 id、level、name、domain、description、source、status 和上下游关系。
5. $domainRisk
6. 验证 JSON 可解析，字段符合 schema 意图。
7. 输出压缩报告：改了什么、L0-L7 链路是什么、哪些仍待裁决、是否建议下一轮接入 CLAUDE.md 工作流。
"@.Trim()
    return [pscustomobject]@{
      Action = 'open_new_pair'
      Title = '建议开新 pair 进入下一阶段'
      Detail = '当前 pair 更像“现状盘点/骨架确认”，继续填真实概念数据属于新目标，建议用新 pair 保持历史清晰。'
      SuggestedPairId = $suggestedPair
      Goal = $goal
      CommandHint = "/workloop $suggestedPair $goal"
    }
  }

  if ($Efficiency -match '低效|返工' -or $Drift -match '偏移') {
    $goal = @"
目标：暂停继续执行，先复核当前 pair 是否目标偏移或陷入低效循环。

任务：
1. 只读取 .ai-relay/pairs/$PairId/ 下的 goal.json、cc-report.md、codex-reply.md、relay-log.md 和 history。
2. 判断当前目标是否仍然成立，是否需要拆成更小的新 pair。
3. 列出最多 3 个下一步选择，并给出推荐项。
4. 不修改业务代码。
"@.Trim()
    return [pscustomobject]@{
      Action = 'review_before_continue'
      Title = '建议先复核目标再继续'
      Detail = '当前总结发现偏移或低效信号，继续让 CC 执行可能扩大成本。'
      SuggestedPairId = $PairId
      Goal = $goal
      CommandHint = "/workloop $PairId $goal"
    }
  }

  $seed = Get-FirstMeaningfulLine $latestNext
  if ([string]::IsNullOrWhiteSpace($seed)) { $seed = Get-FirstMeaningfulLine $GoalText }
  if ([string]::IsNullOrWhiteSpace($seed)) { $seed = '基于当前 pair 总结继续推进一个最小目标' }
  $fallbackGoal = @"
目标：基于当前 pair 的总结继续推进一个最小、可验收的下一步。

上下文：
- 当前 pair：$PairId
- 当前目标：$GoalText
- 可参考：cc-report.md、codex-reply.md、workloop-summary-latest.md。

任务：
1. 先读取当前 pair 的报告、裁决和总结，确认已经完成什么、还缺什么。
2. 只选择一个最小可执行目标，不扩大范围。
3. 不修改业务代码，除非任务明确要求。
4. 完成后写压缩报告，说明修改文件、验证结果、风险和下一步建议。
"@.Trim()
  return [pscustomobject]@{
    Action = 'needs_user_decision'
    Title = '需要你选择下一步'
    Detail = '没有提取到足够明确的下一轮指令。页面提供一个保守的通用目标模板，建议你按实际意图改一句再执行。'
    SuggestedPairId = ConvertTo-WorkloopPairSlug "$PairId`_next" 'next_pair'
    Goal = $fallbackGoal
    CommandHint = "/workloop $PairId $fallbackGoal"
  }
}

function Get-SummarySourceHash {
  param([string]$PairDir)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $builder = [System.Text.StringBuilder]::new()
    # relay-log.md is intentionally excluded: generating or checking a summary
    # appends relay events, which would invalidate the cache immediately.
    foreach ($name in @('pair.json','goal.json','cc-inbox.md','cc-report.md','codex-reply.md')) {
      $path = Join-Path $PairDir $name
      if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path
        [void]$builder.AppendLine("$name|$($item.LastWriteTimeUtc.Ticks)|$($item.Length)")
      } else {
        [void]$builder.AppendLine("$name|missing")
      }
    }
    $historyRoot = Join-Path $PairDir 'history'
    if (Test-Path -LiteralPath $historyRoot) {
      Get-ChildItem -LiteralPath $historyRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('summary.json','cc-inbox.md','cc-report.md','codex-prompt.md','codex-reply.md') } |
        Sort-Object FullName |
        ForEach-Object {
          [void]$builder.AppendLine("$($_.FullName.Substring($PairDir.Length))|$($_.LastWriteTimeUtc.Ticks)|$($_.Length)")
        }
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    $hashBytes = $sha.ComputeHash($bytes)
    return ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Invoke-SummaryAnalyzer {
  param(
    [Parameter(Mandatory=$true)][string]$Analyzer,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$PairDir,
    [Parameter(Mandatory=$true)][string]$PairId,
    [Parameter(Mandatory=$true)][string]$Prompt,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    $PairJson
  )

  if ($Analyzer -eq 'local') { return '' }

  if ($Analyzer -eq 'cc') {
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) { throw "claude CLI not found in PATH." }
    Push-Location $ProjectRoot
    try {
      $output = $Prompt | & $claude.Source --print --permission-mode default --disallowedTools 'Edit,Write,MultiEdit' 2>&1 | Out-String
      if ($LASTEXITCODE -ne 0) {
        throw "Claude Code summary failed with exit code $LASTEXITCODE.`n$output"
      }
      [System.IO.File]::WriteAllText($OutputPath, $output, [System.Text.UTF8Encoding]::new($true))
      Add-AiRelayLog -PairDir $PairDir -Event 'pair-summary-cc' -Detail "Pair summary generated by Claude Code for $PairId."
      return $output.Trim()
    } finally {
      Pop-Location
    }
  }

  if ($Analyzer -eq 'codex') {
    if (-not $PairJson -or -not $PairJson.codexSessionId) {
      throw "pair.json does not contain codexSessionId. Cannot run Codex summary."
    }
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $codex) { throw "codex CLI not found in PATH." }
    $codexSessionId = [string]$PairJson.codexSessionId
    $args = @('exec', '-C', $ProjectRoot, 'resume', '--ignore-user-config', '-c', 'sandbox_mode="read-only"', '-o', $OutputPath, $codexSessionId, '-')
    $oldErrorActionPreference = $ErrorActionPreference
    $oldNativePreference = $null
    $hadNativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
    if ($hadNativePreference) { $oldNativePreference = $PSNativeCommandUseErrorActionPreference }
    try {
      $ErrorActionPreference = 'Continue'
      if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $false }
      $cliOutput = $Prompt | & $codex.Source @args 2>&1 | Out-String
    } finally {
      $ErrorActionPreference = $oldErrorActionPreference
      if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $oldNativePreference }
    }
    Set-Content -LiteralPath ($OutputPath + '.cli.log') -Value $cliOutput -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
      throw "Codex summary failed with exit code $LASTEXITCODE.`n$cliOutput"
    }
    $output = Read-WorkloopFile $OutputPath
    Add-AiRelayLog -PairDir $PairDir -Event 'pair-summary-codex' -Detail "Pair summary generated by Codex for $PairId using explicit session id."
    return $output.Trim()
  }

  throw "Unsupported analyzer: $Analyzer"
}

$projectRoot = Get-AiRelayProjectRoot
$pairId = Get-AiRelayPairId -ProjectRoot $projectRoot -Pair $Pair
Assert-AiRelayPairName $pairId
$pairDir = Get-AiRelayPairDir $projectRoot $pairId
if (-not (Test-Path -LiteralPath $pairDir)) {
  throw "Pair not found: $pairDir"
}

$pairJsonPath = Join-Path $pairDir 'pair.json'
$pair = $null
if (Test-Path -LiteralPath $pairJsonPath) {
  $pair = Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
}

$goalPath = Join-Path $pairDir 'goal.json'
$goal = $null
if (Test-Path -LiteralPath $goalPath) {
  $goal = Get-Content -LiteralPath $goalPath -Raw -Encoding utf8 | ConvertFrom-Json
}

$historyRoot = Join-Path $pairDir 'history'
$roundDirs = @()
if (Test-Path -LiteralPath $historyRoot) {
  $roundDirs = @(Get-ChildItem -LiteralPath $historyRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
}
if ($Last -gt 0 -and $roundDirs.Count -gt $Last) {
  $roundDirs = @($roundDirs | Select-Object -Last $Last)
}

if (-not $OutDir) {
  $OutDir = Join-Path $pairDir 'summary'
}
$summaryRoot = $OutDir
$OutDir = Join-Path $summaryRoot $Analyzer
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$sourceHash = Get-SummarySourceHash -PairDir $pairDir
$summaryArtifactVersion = 'summary-html-artifact-v14'
$latestMdPath = Join-Path $OutDir 'workloop-summary-latest.md'
$latestHtmlPath = Join-Path $OutDir 'workloop-summary-latest.html'
$latestStatePath = Join-Path $OutDir 'workloop-summary-state-latest.json'
$metaPath = Join-Path $OutDir 'workloop-summary-meta.json'

if ($UseCache -and (Test-Path -LiteralPath $latestHtmlPath) -and (Test-Path -LiteralPath $metaPath) -and (Test-Path -LiteralPath $latestStatePath)) {
  try {
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding utf8 | ConvertFrom-Json
    $metaVersion = if ($meta.PSObject.Properties.Name -contains 'artifactVersion') { [string]$meta.artifactVersion } else { '' }
    $stateDoc = Get-Content -LiteralPath $latestStatePath -Raw -Encoding utf8 | ConvertFrom-Json
    $stateVersion = if ($stateDoc.PSObject.Properties.Name -contains 'artifactVersion') { [string]$stateDoc.artifactVersion } else { '' }
    $stateHash = if ($stateDoc.PSObject.Properties.Name -contains 'sourceHash') { [string]$stateDoc.sourceHash } else { '' }
    $hasSummaryState = $stateDoc.PSObject.Properties.Name -contains 'summaryState'
    if ($meta.analyzer -eq $Analyzer -and $meta.sourceHash -eq $sourceHash -and $metaVersion -eq $summaryArtifactVersion -and $stateVersion -eq $summaryArtifactVersion -and $stateHash -eq $sourceHash -and $hasSummaryState) {
      Write-Host "Pair summary cache hit."
      Write-Host "Analyzer: $Analyzer"
      Write-Host "HTML: $latestHtmlPath"
      Write-Host "Markdown: $latestMdPath"
      Write-Host "State: $latestStatePath"
      if ($Open) {
        if ($Format -eq 'md') { Invoke-Item -LiteralPath $latestMdPath } else { Invoke-Item -LiteralPath $latestHtmlPath }
      }
      return
    }
    Write-Host "Pair summary cache miss."
    Write-Host "Analyzer: $Analyzer"
    Write-Host "Expected HTML: $latestHtmlPath"
    Write-Host "原因：总结 HTML、meta 或 state JSON 与当前 pair 数据/模板版本不一致。请点击重新生成总结。"
    if ($CacheOnly) { return }
  } catch {
    Write-Warning "Summary cache metadata is invalid; regenerating. $($_.Exception.Message)"
  }
}

if ($CacheOnly) {
  Write-Host "Pair summary cache miss."
  Write-Host "Analyzer: $Analyzer"
  Write-Host "Expected HTML: $latestHtmlPath"
  if ((Test-Path -LiteralPath $latestHtmlPath) -and -not (Test-Path -LiteralPath $latestStatePath)) {
    Write-Host "原因：已有总结缺少当前版本需要的 state JSON。请点击重新生成总结。"
  } elseif ((Test-Path -LiteralPath $latestHtmlPath) -and (Test-Path -LiteralPath $metaPath)) {
    Write-Host "原因：已有总结与当前 pair 数据或模板版本不一致。请点击重新生成总结。"
  } else {
    Write-Host "原因：没有生成过这个分析方式的总结，或 pair 数据已经变化。请点击重新生成总结。"
  }
  return
}

$goalText = ''
if ($goal -and $goal.goal) { $goalText = [string]$goal.goal }
elseif ($pair -and $pair.task) { $goalText = [string]$pair.task }

$goalStatus = if ($goal -and $goal.status) { [string]$goal.status } else { '未设置 goal.json' }
$roundLimit = if ($goal -and $goal.maxRounds) { [string]$goal.maxRounds } else { '-' }
$goalRound = if ($goal -and $goal.round) { [string]$goal.round } else { '-' }
$lastDecision = if ($goal -and $goal.lastDecision) { [string]$goal.lastDecision } else { '' }
$lastNextInstruction = if ($goal -and $goal.lastNextInstruction) { [string]$goal.lastNextInstruction } else { '' }
$currentInbox = Read-WorkloopFile (Join-Path $pairDir 'cc-inbox.md')
$currentReport = Read-WorkloopFile (Join-Path $pairDir 'cc-report.md')
$currentReply = Read-WorkloopFile (Join-Path $pairDir 'codex-reply.md')

$rounds = @()
$acceptCount = 0
$partialCount = 0
$rejectCount = 0
$unknownCount = 0
$reworkCount = 0
$mojibakeCount = 0
$verificationCount = 0
$fileCounts = @{}
$issueCounts = @{}
$goalKeywords = Get-KeywordSet $goalText
$driftWarnings = New-Object System.Collections.Generic.List[string]

foreach ($dir in $roundDirs) {
  $summaryPath = Join-Path $dir.FullName 'summary.json'
  $summary = $null
  if (Test-Path -LiteralPath $summaryPath) {
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding utf8 | ConvertFrom-Json
  }
  $inbox = Read-WorkloopFile (Join-Path $dir.FullName 'cc-inbox.md')
  $report = Read-WorkloopFile (Join-Path $dir.FullName 'cc-report.md')
  $reply = Read-WorkloopFile (Join-Path $dir.FullName 'codex-reply.md')
  $all = "$inbox`n$report`n$reply"
  $decision = Get-Decision $reply
  switch ($decision) {
    '接受' { $acceptCount++ }
    '部分接受' { $partialCount++ }
    '不接受' { $rejectCount++ }
    default { $unknownCount++ }
  }
  $needsRework = Test-ReworkNeeded $reply
  if ($needsRework) { $reworkCount++ }
  $hasMojibake = $all -match '\?\?\?|锟|�'
  if ($hasMojibake) { $mojibakeCount++ }
  $hasVerification = $report -match '验证|测试|pnpm|npm|passed|failed|typecheck|lint|playwright|vitest'
  if ($hasVerification) { $verificationCount++ }

  foreach ($m in [regex]::Matches($all, '([A-Za-z0-9_\-./\\\[\]]+\.(tsx|jsx|json|yaml|yml|ps1|txt|md|ts|js))')) {
    $file = $m.Value
    if (-not $fileCounts.ContainsKey($file)) { $fileCounts[$file] = 0 }
    $fileCounts[$file]++
  }
  foreach ($m in [regex]::Matches($all, 'TypeError|ReferenceError|SyntaxError|失败|错误|返工|证据不足|缺口|未执行|无法判断|冲突|偏移')) {
    $issue = $m.Value
    if (-not $issueCounts.ContainsKey($issue)) { $issueCounts[$issue] = 0 }
    $issueCounts[$issue]++
  }

  $currentTask = Get-SectionText -Text $report -Heading '当前任务'
  $nextInstruction = Get-CodexNextInstruction $reply
  $overlapText = "$currentTask`n$nextInstruction`n$inbox"
  $overlap = Get-OverlapCount -Needles $goalKeywords -Haystack $overlapText
  if ($goalKeywords.Count -gt 0 -and $overlap -eq 0 -and ($currentTask -or $nextInstruction)) {
    $driftWarnings.Add("轮次 $($dir.Name) 与目标关键词重合度为 0，可能偏离目标。")
  }

  $rounds += [pscustomobject]@{
    Id = $dir.Name
    CreatedAt = if ($summary -and $summary.createdAt) { [string]$summary.createdAt } else { '' }
    Status = if ($summary -and $summary.status) { [string]$summary.status } else { '' }
    Decision = $decision
    NeedsRework = $needsRework
    HasVerification = $hasVerification
    HasMojibake = $hasMojibake
    CurrentTask = Get-CompactText $currentTask 180
    NextInstruction = Get-CompactText $nextInstruction 220
    FullCurrentTask = $currentTask
    FullNextInstruction = $nextInstruction
    ReportSummary = Get-CompactText $report 320
  }
}

$roundCount = @($rounds).Count
$latestRound = if ($rounds) { $rounds[-1] } else { $null }
$hotFiles = @($fileCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8)
$hotIssues = @($issueCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8)
$idleTailCount = 0
for ($idx = $roundCount - 1; $idx -ge 0; $idx--) {
  $roundText = "$($rounds[$idx].CurrentTask)`n$($rounds[$idx].NextInstruction)`n$($rounds[$idx].ReportSummary)"
  if ($roundText -match '无新目标|无待执行|无需下一轮|不需要继续|pair 已结束|保持.*结束|等待用户.*新') {
    $idleTailCount++
  } else {
    break
  }
}
$summaryState = New-WorkloopSummaryState `
  -GoalStatus $goalStatus `
  -GoalText $goalText `
  -LatestRound $latestRound `
  -RoundCount $roundCount `
  -PartialCount $partialCount `
  -RejectCount $rejectCount `
  -ReworkCount $reworkCount `
  -VerificationCount $verificationCount `
  -RawIdleTailCount $idleTailCount `
  -DriftWarningCount $driftWarnings.Count

$overall = [string]$summaryState.Overall
$efficiency = [string]$summaryState.Efficiency
$drift = [string]$summaryState.Drift
$hasIdleLoop = [bool]$summaryState.HasIdleLoop
$idleTailCount = [int]$summaryState.IdleTailCount

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$mdPath = Join-Path $OutDir "workloop-summary-$pairId-$stamp.md"
$htmlPath = Join-Path $OutDir "workloop-summary-$pairId-$stamp.html"
$statePath = Join-Path $OutDir "workloop-summary-state-$pairId-$stamp.json"

$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine("# Pair 会话总结")
[void]$md.AppendLine("")
[void]$md.AppendLine('- Pair: `' + $pairId + '`')
[void]$md.AppendLine('- 项目: `' + $projectRoot + '`')
[void]$md.AppendLine("- 生成时间: $(Get-Date -Format o)")
[void]$md.AppendLine("- 分析方式: 本地规则摘要")
[void]$md.AppendLine("")
[void]$md.AppendLine("## 1. 一句话结论")
[void]$md.AppendLine("")
[void]$md.AppendLine("- 结果: **$overall**")
[void]$md.AppendLine("- 目标偏移: **$drift**")
[void]$md.AppendLine("- 执行效率: **$efficiency**")
[void]$md.AppendLine("")
[void]$md.AppendLine("## 2. 目标和状态")
[void]$md.AppendLine("")
[void]$md.AppendLine("- 目标: $goalText")
[void]$md.AppendLine("- goal 状态: $goalStatus")
[void]$md.AppendLine("- 当前轮次: $goalRound / $roundLimit")
[void]$md.AppendLine("- 最新 Codex 判断: $lastDecision")
[void]$md.AppendLine("- 历史轮次: $roundCount")
[void]$md.AppendLine("")
[void]$md.AppendLine("## 3. 轮次统计")
[void]$md.AppendLine("")
[void]$md.AppendLine("- 接受: $acceptCount")
[void]$md.AppendLine("- 部分接受: $partialCount")
[void]$md.AppendLine("- 不接受: $rejectCount")
[void]$md.AppendLine("- 无法判断: $unknownCount")
[void]$md.AppendLine("- 需要返工/补证据: $reworkCount")
[void]$md.AppendLine("- 有验证信息: $verificationCount")
[void]$md.AppendLine("- 乱码/坏编码信号: $mojibakeCount")
[void]$md.AppendLine("- 尾部空转轮次: $idleTailCount")
[void]$md.AppendLine("")
[void]$md.AppendLine("## 4. 最新下一步")
[void]$md.AppendLine("")
if ($lastNextInstruction) {
  [void]$md.AppendLine($lastNextInstruction)
} elseif ($latestRound -and $latestRound.NextInstruction) {
  [void]$md.AppendLine($latestRound.NextInstruction)
} else {
  [void]$md.AppendLine("没有提取到明确下一步。")
}
[void]$md.AppendLine("")
[void]$md.AppendLine("## 5. 是否可能偏移")
[void]$md.AppendLine("")
if ($driftWarnings.Count -eq 0) {
  [void]$md.AppendLine("- 未发现明显偏移信号。")
} else {
  foreach ($warning in $driftWarnings) { [void]$md.AppendLine("- $warning") }
}
[void]$md.AppendLine("")
[void]$md.AppendLine("## 6. 关键轮次")
foreach ($round in $rounds) {
  [void]$md.AppendLine("")
  [void]$md.AppendLine("### $($round.Id)")
  [void]$md.AppendLine("")
  [void]$md.AppendLine("- 时间: $($round.CreatedAt)")
  [void]$md.AppendLine("- 状态: $($round.Status)")
  [void]$md.AppendLine("- Codex 判断: $($round.Decision)")
  [void]$md.AppendLine("- 需要返工: $($round.NeedsRework)")
  [void]$md.AppendLine("- 有验证信息: $($round.HasVerification)")
  [void]$md.AppendLine("- 乱码信号: $($round.HasMojibake)")
  if ($round.CurrentTask) { [void]$md.AppendLine("- 当前任务: $($round.CurrentTask)") }
  if ($round.NextInstruction) { [void]$md.AppendLine("- 下一步: $($round.NextInstruction)") }
}
[void]$md.AppendLine("")
[void]$md.AppendLine("## 7. 文件热点")
[void]$md.AppendLine("")
if ($hotFiles.Count -eq 0) {
  [void]$md.AppendLine("- 未发现文件路径。")
} else {
  foreach ($item in $hotFiles) { [void]$md.AppendLine('- `' + $item.Key + '`: ' + $item.Value) }
}
[void]$md.AppendLine("")
[void]$md.AppendLine("## 8. 问题热点")
[void]$md.AppendLine("")
if ($hotIssues.Count -eq 0) {
  [void]$md.AppendLine("- 未发现明显问题关键词。")
} else {
  foreach ($item in $hotIssues) { [void]$md.AppendLine('- `' + $item.Key + '`: ' + $item.Value) }
}
[void]$md.AppendLine("")
[void]$md.AppendLine("## 9. 建议")
[void]$md.AppendLine("")
if ($hasIdleLoop) {
  [void]$md.AppendLine("- 建议优先修复 Workloop 空转终止逻辑；当前 pair 已多轮无新任务，不应继续消耗 CC/Codex 额度。")
} elseif ($overall -eq '目标已完成' -or $overall -eq '最近一轮已接受，可能已完成') {
  if ($goalStatus -eq 'completed') {
    [void]$md.AppendLine("- 当前 pair 已完成，建议停止继续执行；如需留档，生成总结或审计后归档。")
  } else {
    [void]$md.AppendLine("- 建议先完成元数据闭环：确认 `.ai-relay/pairs/$pairId/goal.json` 的 `status` 是否应更新为 `completed`，再停止这个 pair；必要时生成完整复盘或审计。")
  }
} elseif ($efficiency -eq '可能低效循环' -or $efficiency -eq '返工偏多') {
  [void]$md.AppendLine("- 建议暂停继续执行，让 Codex 或人工重新收敛目标和验收标准。")
} elseif ($drift -eq '可能偏移') {
  [void]$md.AppendLine("- 建议先更新目标或重新规划任务，再让 CC 继续。")
} else {
  [void]$md.AppendLine("- 可以继续下一轮，但下一条任务应该保持单一目标和明确验收。")
}
[void]$md.AppendLine("")

$latestRoundNextInstruction = if ($latestRound -and $latestRound.NextInstruction) { [string]$latestRound.NextInstruction } else { '' }
$nextMove = Get-WorkloopNextMove `
  -PairId $pairId `
  -ProjectRoot $projectRoot `
  -GoalText $goalText `
  -GoalStatus $goalStatus `
  -Overall $overall `
  -Efficiency $efficiency `
  -Drift $drift `
  -LastNextInstruction $lastNextInstruction `
  -LatestRoundNextInstruction $latestRoundNextInstruction `
  -Inbox $currentInbox `
  -Report $currentReport `
  -Reply $currentReply `
  -LocalSummary ''

[void]$md.AppendLine("## 10. 下一步推进指令")
[void]$md.AppendLine("")
[void]$md.AppendLine("- 建议动作: $($nextMove.Title)")
[void]$md.AppendLine("- 建议 pair: ``$($nextMove.SuggestedPairId)``")
[void]$md.AppendLine("- 理由: $($nextMove.Detail)")
[void]$md.AppendLine("")
[void]$md.AppendLine("### 可直接复制的目标指令")
[void]$md.AppendLine("")
[void]$md.AppendLine('```text')
[void]$md.AppendLine($nextMove.Goal)
[void]$md.AppendLine('```')

$localMdText = $md.ToString()
$mdText = $localMdText
$encoding = [System.Text.UTF8Encoding]::new($true)
$agentText = ''

if ($RenderOnly) {
  if (-not (Test-Path -LiteralPath $latestMdPath)) {
    throw "RenderOnly requires existing markdown: $latestMdPath"
  }
  $mdText = Get-Content -LiteralPath $latestMdPath -Raw -Encoding utf8
  $agentText = $mdText
} elseif ($Analyzer -ne 'local') {
  $analysisPath = Join-Path $OutDir "workloop-summary-$pairId-$stamp-$Analyzer-analysis.md"
  $promptPath = Join-Path $OutDir "workloop-summary-$pairId-$stamp-$Analyzer-prompt.md"
  $prompt = @"
你正在为 Agent Workloop pair 生成中文会话总结。

要求：
1. 正常分析当前项目和 pair 数据；可以读取项目文件，但不要修改任何文件。
2. 重点判断：目标是否完成、是否偏移、是否低效循环、最终结果怎样、下一步是什么。
3. 不要贴大段日志，不要贴完整 diff。
4. 输出中文 Markdown，面向用户阅读。
5. 如果证据不足，明确说证据不足，不要编造。
6. 不要创建计划文件，不要写入项目文件，直接在最终回答中输出总结。
7. 不要反问用户“想怎么做”；你必须给出自己的推荐动作和理由。
8. 必须使用下面的七个二级标题，不要换成表格式问答。

项目目录：
$projectRoot

Pair 目录：
$pairDir

建议优先读取：
- .ai-relay/pairs/$pairId/pair.json
- .ai-relay/pairs/$pairId/goal.json
- .ai-relay/pairs/$pairId/cc-report.md
- .ai-relay/pairs/$pairId/codex-reply.md
- .ai-relay/pairs/$pairId/relay-log.md
- .ai-relay/pairs/$pairId/history/

请按这个结构输出：

# Pair 会话总结

## 1. 最终结论
用 3-6 条说明这个 pair 当前到底完成了什么、没完成什么。

## 2. 目标是否偏移
判断是否偏离原目标，并给理由。

## 3. 执行效率
判断是否反复修同一个问题、是否低效、是否需要暂停。

## 4. 关键证据
列出你依据的报告、裁决、历史轮次或项目文件。

## 5. 风险和缺口
列出未验证、证据不足、冲突风险。

## 6. 下一步建议
给一个最小、可执行的下一步。

## 7. 下一步推进指令
必须包含：
- 建议动作：继续当前 pair / 开新 pair / 关闭 pair / 需要用户裁决。
- 建议 pairId：如果建议开新 pair，给出合法 pairId。
- 可直接复制的目标指令：写成能直接交给 Workloop/Claude Code 的中文任务，不要只写一句口号。

下面是本地规则先生成的摘要，供你参考，但你可以基于项目文件修正它：

$localMdText
"@
  [System.IO.File]::WriteAllText($promptPath, $prompt, $encoding)
  $agentText = Invoke-SummaryAnalyzer -Analyzer $Analyzer -ProjectRoot $projectRoot -PairDir $pairDir -PairId $pairId -Prompt $prompt -OutputPath $analysisPath -PairJson $pair
  $mdText = @"
# Pair 会话总结

- Pair: $pairId
- 项目: $projectRoot
- 生成时间: $(Get-Date -Format o)
- 分析方式: $Analyzer

$agentText

---

# 本地规则摘要

$localMdText
"@
}

$decisionText = "$localMdText`n$agentText"
$displayOverall = [string]$summaryState.Overall
$displayEfficiency = [string]$summaryState.Efficiency
$displayDrift = [string]$summaryState.Drift
$nextMove = Get-WorkloopNextMove `
  -PairId $pairId `
  -ProjectRoot $projectRoot `
  -GoalText $goalText `
  -GoalStatus $goalStatus `
  -Overall $displayOverall `
  -Efficiency $displayEfficiency `
  -Drift $displayDrift `
  -LastNextInstruction $lastNextInstruction `
  -LatestRoundNextInstruction $latestRoundNextInstruction `
  -Inbox $currentInbox `
  -Report $currentReport `
  -Reply $currentReply `
  -LocalSummary ''
$finalNextBuilder = [System.Text.StringBuilder]::new()
[void]$finalNextBuilder.AppendLine('## 10. 下一步推进指令')
[void]$finalNextBuilder.AppendLine('')
[void]$finalNextBuilder.AppendLine("- 建议动作: $($nextMove.Title)")
[void]$finalNextBuilder.AppendLine("- 建议 pair: ``$($nextMove.SuggestedPairId)``")
[void]$finalNextBuilder.AppendLine("- 理由: $($nextMove.Detail)")
[void]$finalNextBuilder.AppendLine('')
[void]$finalNextBuilder.AppendLine('### 可直接复制的目标指令')
[void]$finalNextBuilder.AppendLine('')
[void]$finalNextBuilder.AppendLine('```text')
[void]$finalNextBuilder.AppendLine([string]$nextMove.Goal)
[void]$finalNextBuilder.AppendLine('```')
$finalNextSection = $finalNextBuilder.ToString().TrimEnd()
$mdText = [regex]::Replace($mdText, '(?ms)^## 10\. 下一步推进指令\s*.*\z', $finalNextSection)

if ($Format -eq 'md' -or $Format -eq 'both') {
  [System.IO.File]::WriteAllText($mdPath, $mdText, $encoding)
  [System.IO.File]::WriteAllText($latestMdPath, $mdText, $encoding)
}

if ($Format -eq 'html' -or $Format -eq 'both') {
  $statusCards = @(
    [pscustomobject]@{ Label = '当前结论'; Value = $displayOverall; Tone = Get-SummaryTone $displayOverall },
    [pscustomobject]@{ Label = '目标偏移'; Value = $displayDrift; Tone = Get-SummaryTone $displayDrift },
    [pscustomobject]@{ Label = '执行效率'; Value = $displayEfficiency; Tone = Get-SummaryTone $displayEfficiency },
    [pscustomobject]@{ Label = '是否需要介入'; Value = if ($summaryState.NeedsUser) { '建议查看' } else { '暂不需要' }; Tone = if ($summaryState.NeedsUser) { 'warn' } else { 'good' } }
  )
  $cardsHtml = [System.Text.StringBuilder]::new()
  foreach ($card in $statusCards) {
    [void]$cardsHtml.AppendLine("<article class=""metric $($card.Tone)""><span>$(Encode-Html $card.Label)</span><strong>$(Encode-Html $card.Value)</strong></article>")
  }
  $nextInstructionText = if (-not [string]::IsNullOrWhiteSpace($nextMove.Goal)) { [string]$nextMove.Goal } elseif ($lastNextInstruction) { $lastNextInstruction } elseif ($latestRound -and $latestRound.NextInstruction) { $latestRound.NextInstruction } else { '没有提取到明确下一步。' }
  $isTerminalNextMove = ([string]$nextMove.Action) -eq 'close_pair'
  $recommendation = if ($displayOverall -eq '目标已完成' -or $displayOverall -eq '最近一轮已接受，可能已完成') {
    "建议收口这个 pair：先确认 goal.json 的 status 是否应更新为 completed，再停止 pair；必要时生成审计或复盘留档。"
  } elseif ($displayEfficiency -match '低效|返工|空转') {
    '建议暂停继续执行，先由 Codex 或人工重新收敛目标和验收标准。'
  } elseif ($displayDrift -eq '可能偏移') {
    '建议先更新目标或重新规划任务，再让 Claude Code 继续。'
  } else {
    '可以继续下一轮，但下一条任务应保持单一目标和明确验收。'
  }
  $recommendation = "$($nextMove.Title)：$($nextMove.Detail)"
  $authoritativeNextHtml = @"
<div class="authoritative-next">
  <h3>当前权威下一步</h3>
  <dl class="mini-kv">
    <dt>动作</dt><dd>$(Encode-Html $nextMove.Title)</dd>
    <dt>建议 Pair</dt><dd><code>$(Encode-Html $nextMove.SuggestedPairId)</code></dd>
    <dt>理由</dt><dd>$(Encode-Html $nextMove.Detail)</dd>
  </dl>
  <pre class="copy-block">$(Encode-Html $nextInstructionText)</pre>
</div>
"@

  $timeline = [System.Text.StringBuilder]::new()
  if ($rounds.Count -eq 0) {
    [void]$timeline.AppendLine('<p class="muted">还没有历史轮次。</p>')
  } else {
    foreach ($round in $rounds) {
      $tone = Get-SummaryTone "$($round.Decision) $($round.Status) $($round.NeedsRework)"
      [void]$timeline.AppendLine("<article class=""round $tone"">")
      [void]$timeline.AppendLine("<div class=""round-head""><strong>$(Encode-Html $round.Id)</strong><span>$(Encode-Html $round.Decision)</span></div>")
      [void]$timeline.AppendLine("<dl class=""round-grid"">")
      [void]$timeline.AppendLine("<dt>时间</dt><dd>$(Encode-Html $round.CreatedAt)</dd>")
      [void]$timeline.AppendLine("<dt>状态</dt><dd>$(Encode-Html $round.Status)</dd>")
      [void]$timeline.AppendLine("<dt>返工</dt><dd>$(Encode-Html ([string]$round.NeedsRework))</dd>")
      [void]$timeline.AppendLine("<dt>验证</dt><dd>$(Encode-Html ([string]$round.HasVerification))</dd>")
      $roundOverviewParts = @()
      if ($round.CurrentTask) { $roundOverviewParts += "任务：$(Get-CompactLine ([string]$round.CurrentTask) 110)" }
      if ($round.NextInstruction) { $roundOverviewParts += "下一步：$(Get-CompactLine ([string]$round.NextInstruction) 140)" }
      if ($roundOverviewParts.Count -gt 0) {
        [void]$timeline.AppendLine("<dt>概览</dt><dd><div class=""timeline-excerpt"">$(Convert-TimelineTextToHtml ($roundOverviewParts -join ' / '))</div></dd>")
      }
      [void]$timeline.AppendLine("</dl>")
      if ($round.FullCurrentTask -or $round.FullNextInstruction) {
        [void]$timeline.AppendLine('<details class="round-detail" open>')
        [void]$timeline.AppendLine('<summary>查看完整任务和下一步</summary>')
        if ($round.FullCurrentTask) {
          [void]$timeline.AppendLine('<h4>完整任务</h4>')
          [void]$timeline.AppendLine("<pre>$(Encode-Html $round.FullCurrentTask)</pre>")
        }
        if ($round.FullNextInstruction) {
          [void]$timeline.AppendLine('<h4>完整下一步</h4>')
          [void]$timeline.AppendLine("<pre>$(Encode-Html $round.FullNextInstruction)</pre>")
        }
        [void]$timeline.AppendLine('</details>')
      }
      [void]$timeline.AppendLine("</article>")
    }
  }

  $hotFilesHtml = [System.Text.StringBuilder]::new()
  if ($hotFiles.Count -eq 0) {
    [void]$hotFilesHtml.AppendLine('<p class="muted">未发现文件路径。</p>')
  } else {
    [void]$hotFilesHtml.AppendLine('<ul class="evidence-list">')
    foreach ($item in $hotFiles) {
      $filePath = [string]$item.Key
      $fileUri = Convert-PathToFileUri -ProjectRoot $projectRoot -Path $filePath
      $fileLabel = if ($fileUri) {
        "<a href=""$(Encode-Html $fileUri)""><code>$(Encode-Html $filePath)</code></a><small>可打开本地文件</small>"
      } else {
        "<code>$(Encode-Html $filePath)</code><small>未在当前项目中找到可打开路径</small>"
      }
      [void]$hotFilesHtml.AppendLine("<li><span>$fileLabel</span><strong>$(Encode-Html ([string]$item.Value)) 次</strong></li>")
    }
    [void]$hotFilesHtml.AppendLine('</ul>')
  }

  $hotIssuesHtml = [System.Text.StringBuilder]::new()
  if ($hotIssues.Count -eq 0) {
    [void]$hotIssuesHtml.AppendLine('<p class="muted">未发现明显问题关键词。</p>')
  } else {
    [void]$hotIssuesHtml.AppendLine('<ul class="evidence-list">')
    foreach ($item in $hotIssues) {
      [void]$hotIssuesHtml.AppendLine("<li><code>$(Encode-Html $item.Key)</code><span>$(Encode-Html ([string]$item.Value)) 次</span></li>")
    }
    [void]$hotIssuesHtml.AppendLine('</ul>')
  }

  $driftHtml = if ($driftWarnings.Count -eq 0) {
    '<p class="muted">未发现明显偏移信号。</p>'
  } else {
    New-SummaryListHtml -Items $driftWarnings -EmptyText '未发现明显偏移信号。'
  }
  $agentHtml = if ($Analyzer -ne 'local' -and -not [string]::IsNullOrWhiteSpace($agentText)) {
    $displayAgentText = if ($isTerminalNextMove) {
      Convert-AgentNextSectionsForTerminalPair -Markdown $agentText -AuthoritativeTitle ([string]$nextMove.Title)
    } else {
      $agentText
    }
    Convert-SimpleMarkdownToHtml $displayAgentText
  } else {
    Convert-SimpleMarkdownToHtml $localMdText
  }
  $artifactSourceText = "$goalText`n$currentInbox`n$currentReport`n$currentReply`n$localMdText`n$agentText"
  $structureHtml = New-KnowledgePyramidSvgHtml -AllText $artifactSourceText

  $evidenceTerms = @('完成状态','风险','下一步','证据','验证','空壳','domain','concept','schema','CLAUDE.md','返工','接受','不接受','部分接受')
  $evidenceSnippets = @()
  foreach ($source in @(
    [pscustomobject]@{ Name = 'cc-report.md'; Text = $currentReport },
    [pscustomobject]@{ Name = 'codex-reply.md'; Text = $currentReply },
    [pscustomobject]@{ Name = 'cc-inbox.md'; Text = $currentInbox }
  )) {
    foreach ($snippet in (Get-EvidenceSnippets -Text $source.Text -Terms $evidenceTerms -Limit 5)) {
      $evidenceSnippets += [pscustomobject]@{
        Source = $source.Name
        Term = $snippet.Term
        Line = $snippet.Line
        Text = $snippet.Text
      }
    }
  }
  $evidenceCardsHtml = [System.Text.StringBuilder]::new()
  if ($evidenceSnippets.Count -eq 0) {
    [void]$evidenceCardsHtml.AppendLine('<p class="muted">没有提取到可展开证据片段。</p>')
  } else {
    foreach ($snippet in ($evidenceSnippets | Select-Object -First 10)) {
      [void]$evidenceCardsHtml.AppendLine('<details class="evidence-card">')
      [void]$evidenceCardsHtml.AppendLine("<summary><span>$(Encode-Html $snippet.Source)</span><strong>$(Encode-Html $snippet.Term)</strong><em>line $(Encode-Html ([string]$snippet.Line))</em></summary>")
      [void]$evidenceCardsHtml.AppendLine("<pre>$(Encode-Html $snippet.Text)</pre>")
      [void]$evidenceCardsHtml.AppendLine('</details>')
    }
  }

  $navItemsHtml = @(
    '<a href="#overview">结论</a>',
    '<a href="#structure">结构图</a>',
    '<a href="#analysis">分析</a>',
    '<a href="#timeline">时间线</a>',
    '<a href="#evidence">证据</a>',
    '<a href="#next">下一步</a>'
  ) -join ''
  $rawMdHtml = Encode-Html $mdText
  $html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Pair 会话总结 - $pairId</title>
  <style>
    :root { color-scheme: light; --bg:#f4f2ed; --panel:#ffffff; --ink:#17202a; --muted:#66717f; --line:#d9ded7; --soft:#f7f8f4; --good:#176b5d; --warn:#8a5a00; --bad:#9b2c2c; --accent:#0f766e; }
    * { box-sizing:border-box; }
    body { margin:0; background:var(--bg); color:var(--ink); font-family:"Segoe UI","Microsoft YaHei",Arial,sans-serif; line-height:1.62; }
    main { max-width:1320px; margin:0 auto; padding:28px; }
    header { display:flex; justify-content:space-between; gap:24px; align-items:flex-start; margin-bottom:20px; }
    h1 { margin:0 0 8px; font-size:30px; letter-spacing:0; }
    h2 { margin:0 0 14px; font-size:20px; }
    h3 { margin:18px 0 10px; font-size:16px; color:#344054; }
    code { background:#eef1ec; border:1px solid #dce2da; border-radius:4px; padding:1px 5px; }
    pre { white-space:pre-wrap; overflow-wrap:anywhere; background:#111713; color:#e8eee9; border:1px solid #303a32; border-radius:8px; padding:14px; max-height:560px; overflow:auto; }
    a { color:var(--accent); text-decoration:none; }
    a:hover { text-decoration:underline; }
    .muted { color:var(--muted); }
    .meta { color:var(--muted); font-size:13px; }
    .topnav { position:sticky; top:0; z-index:20; background:rgba(244,242,237,.94); backdrop-filter:blur(8px); border-bottom:1px solid var(--line); margin:0 -28px 20px; padding:10px 28px; display:flex; gap:8px; flex-wrap:wrap; }
    .topnav a { border:1px solid var(--line); border-radius:999px; background:#fff; padding:6px 11px; color:#344054; font-size:13px; }
    .layout { display:grid; grid-template-columns:minmax(0,1fr) 340px; gap:18px; align-items:start; }
    .stack { display:grid; gap:18px; }
    .panel { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:18px; }
    .hero { background:#13211d; color:#f6faf6; border-color:#30453e; }
    .hero .meta, .hero code { color:#d7e5dd; }
    .metrics { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; }
    .metric { border:1px solid var(--line); border-radius:8px; padding:12px; background:var(--soft); min-height:90px; }
    .metric span { display:block; color:var(--muted); font-size:13px; margin-bottom:8px; }
    .metric strong { display:block; font-size:20px; line-height:1.25; }
    .metric.good { border-color:#8ab8a8; background:#eef8f2; color:var(--good); }
    .metric.warn { border-color:#d9b56c; background:#fff7e6; color:var(--warn); }
    .metric.bad { border-color:#d79a9a; background:#fff1f1; color:var(--bad); }
    .two-col { display:grid; grid-template-columns:1fr 1fr; gap:14px; }
    .kv { display:grid; grid-template-columns:110px minmax(0,1fr); gap:8px 12px; }
    .kv dt, .round-grid dt { color:var(--muted); }
    .kv dd, .round-grid dd { margin:0; min-width:0; overflow-wrap:anywhere; word-break:break-word; }
    .round { border-left:4px solid #aab4ad; background:var(--soft); border-radius:8px; padding:12px 14px; margin-bottom:12px; overflow:hidden; }
    .round.good { border-left-color:var(--good); }
    .round.warn { border-left-color:var(--warn); }
    .round.bad { border-left-color:var(--bad); }
    .round-head { display:flex; justify-content:space-between; gap:12px; align-items:center; margin-bottom:8px; }
    .round-head span { border:1px solid var(--line); border-radius:999px; padding:2px 9px; background:#fff; }
    .round-grid { display:grid; grid-template-columns:76px minmax(0,1fr); gap:6px 10px; margin:0; }
    .round-grid code, .timeline-excerpt code { white-space:normal; overflow-wrap:anywhere; word-break:break-word; }
    .timeline-excerpt { max-width:100%; overflow-wrap:anywhere; word-break:break-word; }
    .round-detail { margin-top:10px; border-top:1px solid #edf0eb; padding-top:8px; }
    .round-detail h4 { margin:10px 0 6px; font-size:13px; color:var(--muted); }
    .round-detail pre { margin:8px 0 0; max-height:420px; }
    .evidence-list, .compact-list { list-style:none; padding:0; margin:0; display:grid; gap:8px; }
    .evidence-list li { display:flex; justify-content:space-between; gap:12px; border-bottom:1px solid #edf0eb; padding-bottom:8px; align-items:flex-start; }
    .evidence-list small { display:block; color:var(--muted); }
    .evidence-card { border:1px solid var(--line); border-radius:8px; padding:10px 12px; background:#fbfcfa; margin-bottom:8px; }
    .evidence-card summary { display:grid; grid-template-columns:110px minmax(0,1fr) auto; gap:10px; align-items:center; cursor:pointer; }
    .evidence-card summary span { color:var(--muted); }
    .evidence-card summary em { color:var(--muted); font-style:normal; font-size:12px; }
    .evidence-card pre { margin:10px 0 0; max-height:260px; }
    .content-html h1 { font-size:22px; margin-top:0; }
    .content-html h2 { border-top:1px solid var(--line); padding-top:16px; margin-top:20px; }
    .content-html ul { padding-left:20px; }
    .table-wrap { overflow:auto; border:1px solid var(--line); border-radius:8px; margin:12px 0; }
    .table-wrap table { width:100%; min-width:560px; border-collapse:collapse; background:#fff; }
    .table-wrap th, .table-wrap td { border-bottom:1px solid #edf0eb; padding:9px 10px; text-align:left; vertical-align:top; }
    .table-wrap th { background:#f5f6f2; color:#344054; font-weight:700; }
    .table-wrap tr:last-child td { border-bottom:0; }
    .pyramid-wrap { overflow:auto; border:1px solid var(--line); border-radius:8px; background:#fff; }
    .pyramid-wrap svg { width:100%; min-width:720px; display:block; }
    .svg-title { font:700 22px "Segoe UI","Microsoft YaHei",Arial,sans-serif; fill:#17202a; }
    .svg-subtitle { font:13px "Segoe UI","Microsoft YaHei",Arial,sans-serif; fill:#66717f; }
    .svg-line { stroke:#bdc9bf; stroke-width:1.2; }
    .layer { font:600 13px "Segoe UI","Microsoft YaHei",Arial,sans-serif; fill:#24322d; }
    .status { stroke-width:1.5; }
    .status.ok { fill:#edf8f1; stroke:#7ca88f; }
    .status.warn { fill:#fff7e6; stroke:#d9b56c; }
    .status.bad { fill:#fff1f1; stroke:#d79a9a; }
    .status-title { font:700 14px "Segoe UI","Microsoft YaHei",Arial,sans-serif; fill:#17202a; }
    .status-text { font:12px "Segoe UI","Microsoft YaHei",Arial,sans-serif; fill:#46525f; }
    aside { position:sticky; top:18px; }
    .action { background:#fff8e8; border-color:#e3c071; }
    .tool-button { border:1px solid var(--accent); border-radius:6px; background:#e7f2ed; color:var(--accent); padding:8px 10px; font:inherit; cursor:pointer; width:100%; text-align:center; }
    .tool-button:hover { background:#d9eee6; }
    .next-plan { display:grid; gap:12px; }
    .next-plan .mini-kv { display:grid; grid-template-columns:84px minmax(0,1fr); gap:6px 10px; margin:0; }
    .next-plan .mini-kv dt { color:var(--muted); }
    .next-plan .mini-kv dd { margin:0; overflow-wrap:anywhere; }
    .authoritative-next { border:1px solid #7ba896; border-left:5px solid var(--accent); border-radius:8px; padding:14px 16px; background:#f3faf6; margin-bottom:18px; }
    .authoritative-next h3 { margin-top:0; }
    .authoritative-next .mini-kv { display:grid; grid-template-columns:84px minmax(0,1fr); gap:6px 10px; margin:0 0 12px; }
    .authoritative-next .mini-kv dt { color:var(--muted); }
    .authoritative-next .mini-kv dd { margin:0; overflow-wrap:anywhere; }
    .copy-block { max-height:420px; margin:0; background:#101915; }
    details summary { cursor:pointer; font-weight:600; }
    @media (max-width: 980px) { main { padding:16px; } header, .layout { display:block; } aside { position:static; margin-top:18px; } .metrics, .two-col { grid-template-columns:1fr; } }
  </style>
</head>
<body>
<main>
  <nav class="topnav">
    $navItemsHtml
  </nav>
  <header>
    <div>
      <h1>Pair 会话复盘</h1>
      <div class="meta">Pair <code>$(Encode-Html $pairId)</code> · $(Encode-Html $Analyzer) · $(Encode-Html (Get-Date -Format o))</div>
    </div>
    <div class="meta">项目：<code>$(Encode-Html $projectRoot)</code></div>
  </header>

  <section id="overview" class="panel hero">
    <h2>当前判断</h2>
    <div class="metrics">
      $($cardsHtml.ToString())
    </div>
  </section>

  <div class="layout">
    <div class="stack">
      <section class="panel">
        <h2>目标和状态</h2>
        <dl class="kv">
          <dt>目标</dt><dd>$(Convert-InlineMarkdownToHtml $goalText)</dd>
          <dt>goal 状态</dt><dd>$(Encode-Html $goalStatus)</dd>
          <dt>当前轮次</dt><dd>$(Encode-Html "$goalRound / $roundLimit")</dd>
          <dt>历史轮次</dt><dd>$(Encode-Html ([string]$roundCount))</dd>
          <dt>最新裁决</dt><dd>$(Encode-Html $lastDecision)</dd>
        </dl>
      </section>

      <section id="structure" class="panel">
        <h2>结构视图</h2>
        $structureHtml
      </section>

      <section id="analysis" class="panel">
        <h2>AI 分析摘要</h2>
        $authoritativeNextHtml
        <div class="content-html">
          $agentHtml
        </div>
      </section>

      <section id="timeline" class="panel">
        <h2>轮次时间线</h2>
        $($timeline.ToString())
      </section>

      <section id="evidence" class="panel">
        <h2>证据和热点</h2>
        <div class="two-col">
          <div>
            <h3>文件热点</h3>
            $($hotFilesHtml.ToString())
          </div>
          <div>
            <h3>问题热点</h3>
            $($hotIssuesHtml.ToString())
          </div>
        </div>
        <h3>目标偏移信号</h3>
        $driftHtml
        <h3>证据片段</h3>
        $($evidenceCardsHtml.ToString())
      </section>

      <section class="panel">
        <details>
          <summary>查看原始 Markdown</summary>
          <pre>$rawMdHtml</pre>
        </details>
      </section>
    </div>

    <aside class="stack">
      <section class="panel action">
        <h2>推荐动作</h2>
        <p><strong>$(Encode-Html $recommendation)</strong></p>
      </section>
      <section id="next" class="panel">
        <h2>下一步推进建议</h2>
        <div class="next-plan">
          <dl class="mini-kv">
            <dt>动作</dt><dd>$(Encode-Html $nextMove.Title)</dd>
            <dt>建议 Pair</dt><dd><code>$(Encode-Html $nextMove.SuggestedPairId)</code></dd>
            <dt>理由</dt><dd>$(Encode-Html $nextMove.Detail)</dd>
          </dl>
          <h3>可直接复制的目标指令</h3>
          <pre id="next-instruction" class="copy-block">$(Encode-Html $nextInstructionText)</pre>
        </div>
        <button class="tool-button" type="button" data-copy-target="next-instruction">复制下一步</button>
      </section>
      <section class="panel">
        <h2>风险快照</h2>
        <dl class="kv">
          <dt>返工轮次</dt><dd>$(Encode-Html ([string]$reworkCount))</dd>
          <dt>验证轮次</dt><dd>$(Encode-Html ([string]$verificationCount))</dd>
          <dt>乱码信号</dt><dd>$(Encode-Html ([string]$mojibakeCount))</dd>
          <dt>部分/拒绝</dt><dd>$(Encode-Html "$partialCount / $rejectCount")</dd>
        </dl>
      </section>
    </aside>
  </div>
</main>
<script>
  document.querySelectorAll('[data-copy-target]').forEach((button) => {
    button.addEventListener('click', async () => {
      const id = button.getAttribute('data-copy-target');
      const node = document.getElementById(id);
      const text = node ? node.innerText.trim() : '';
      if (!text) return;
      try {
        await navigator.clipboard.writeText(text);
        const old = button.textContent;
        button.textContent = '已复制';
        setTimeout(() => { button.textContent = old; }, 1200);
      } catch {
        window.prompt('复制失败，请手动复制：', text);
      }
    });
  });
</script>
</body>
</html>
"@
  [System.IO.File]::WriteAllText($htmlPath, $html, $encoding)
  [System.IO.File]::WriteAllText($latestHtmlPath, $html, $encoding)
}

$statePayload = [ordered]@{
  pairId = $pairId
  projectRoot = $projectRoot
  analyzer = $Analyzer
  sourceHash = $sourceHash
  artifactVersion = $summaryArtifactVersion
  generatedAt = (Get-Date).ToString('o')
  summaryState = ([ordered]@{
    diagnosis = [string]$summaryState.Diagnosis
    overall = [string]$summaryState.Overall
    efficiency = [string]$summaryState.Efficiency
    drift = [string]$summaryState.Drift
    hasIdleLoop = [bool]$summaryState.HasIdleLoop
    idleTailCount = [int]$summaryState.IdleTailCount
    needsUser = [bool]$summaryState.NeedsUser
  })
  stats = ([ordered]@{
    roundCount = [int]$roundCount
    acceptCount = [int]$acceptCount
    partialCount = [int]$partialCount
    rejectCount = [int]$rejectCount
    unknownCount = [int]$unknownCount
    reworkCount = [int]$reworkCount
    verificationCount = [int]$verificationCount
    mojibakeCount = [int]$mojibakeCount
  })
  latest = ([ordered]@{
    goalStatus = $goalStatus
    goalRound = $goalRound
    roundLimit = $roundLimit
    lastDecision = $lastDecision
    lastNextInstruction = $lastNextInstruction
    latestHistoryId = if ($latestRound) { [string]$latestRound.Id } else { '' }
  })
  nextMove = ([ordered]@{
    action = [string]$nextMove.Action
    title = [string]$nextMove.Title
    detail = [string]$nextMove.Detail
    suggestedPairId = [string]$nextMove.SuggestedPairId
  })
  paths = ([ordered]@{
    markdown = $mdPath
    html = $htmlPath
    latestMarkdown = $latestMdPath
    latestHtml = $latestHtmlPath
  })
}
Write-AiRelayJson $statePayload $statePath
Write-AiRelayJson $statePayload $latestStatePath

Write-AiRelayJson ([ordered]@{
  pairId = $pairId
  projectRoot = $projectRoot
  analyzer = $Analyzer
  sourceHash = $sourceHash
  artifactVersion = $summaryArtifactVersion
  cacheHashAlgorithm = 'v2-no-relay-log'
  state = $latestStatePath
  summaryState = $statePayload.summaryState
  generatedAt = (Get-Date).ToString('o')
  markdown = $mdPath
  html = $htmlPath
  latestMarkdown = $latestMdPath
  latestHtml = $latestHtmlPath
  latestState = $latestStatePath
}) $metaPath

Write-Host "Pair summary generated:"
Write-Host "Analyzer: $Analyzer"
if ($Format -eq 'md' -or $Format -eq 'both') {
  Write-Host "Markdown: $mdPath"
  Write-Host "Latest Markdown: $latestMdPath"
}
if ($Format -eq 'html' -or $Format -eq 'both') {
  Write-Host "HTML: $htmlPath"
  Write-Host "Latest HTML: $latestHtmlPath"
}
if ($Open) {
  if ($Format -eq 'md') { Invoke-Item -LiteralPath $mdPath } else { Invoke-Item -LiteralPath $htmlPath }
}

