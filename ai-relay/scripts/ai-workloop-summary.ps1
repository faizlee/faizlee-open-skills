param(
  [string]$Pair,
  [int]$Last = 0,
  [ValidateSet('cc','codex','local')][string]$Analyzer = 'cc',
  [ValidateSet('md','html','both')][string]$Format = 'both',
  [string]$OutDir,
  [switch]$UseCache,
  [switch]$CacheOnly,
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

function Get-SummarySourceHash {
  param([string]$PairDir)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $builder = [System.Text.StringBuilder]::new()
    foreach ($name in @('pair.json','goal.json','cc-inbox.md','cc-report.md','codex-reply.md','relay-log.md')) {
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
$latestMdPath = Join-Path $OutDir 'workloop-summary-latest.md'
$latestHtmlPath = Join-Path $OutDir 'workloop-summary-latest.html'
$metaPath = Join-Path $OutDir 'workloop-summary-meta.json'

if ($UseCache -and (Test-Path -LiteralPath $latestHtmlPath) -and (Test-Path -LiteralPath $metaPath)) {
  try {
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($meta.analyzer -eq $Analyzer -and $meta.sourceHash -eq $sourceHash) {
      Write-Host "Pair summary cache hit."
      Write-Host "Analyzer: $Analyzer"
      Write-Host "HTML: $latestHtmlPath"
      Write-Host "Markdown: $latestMdPath"
      if ($Open) {
        if ($Format -eq 'md') { Invoke-Item -LiteralPath $latestMdPath } else { Invoke-Item -LiteralPath $latestHtmlPath }
      }
      return
    }
  } catch {
    Write-Warning "Summary cache metadata is invalid; regenerating. $($_.Exception.Message)"
  }
}

if ($CacheOnly) {
  Write-Host "Pair summary cache miss."
  Write-Host "Analyzer: $Analyzer"
  Write-Host "Expected HTML: $latestHtmlPath"
  Write-Host "原因：没有生成过这个分析方式的总结，或 pair 数据已经变化。请点击重新生成总结。"
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

  foreach ($m in [regex]::Matches($all, '([A-Za-z0-9_\-./\\\[\]]+\.(tsx|ts|js|jsx|json|md|ps1|yml|yaml|txt))')) {
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
    ReportSummary = Get-CompactText $report 320
  }
}

$roundCount = @($rounds).Count
$latestRound = if ($rounds) { $rounds[-1] } else { $null }
$hotFiles = @($fileCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8)
$hotIssues = @($issueCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8)

$overall = '无法判断'
if ($goalStatus -eq 'completed') { $overall = '目标已完成' }
elseif ($goalStatus -eq 'stopped') { $overall = '目标已停止，需要人工判断' }
elseif ($latestRound -and $latestRound.Decision -eq '接受' -and -not $lastNextInstruction) { $overall = '最近一轮已接受，可能已完成' }
elseif ($latestRound -and $latestRound.Decision -eq '部分接受') { $overall = '部分完成，仍有后续任务或验证缺口' }
elseif ($latestRound -and $latestRound.Decision -eq '不接受') { $overall = '未通过，需要返工' }
elseif ($roundCount -eq 0) { $overall = '还没有历史轮次' }

$efficiency = '正常'
if ($roundCount -ge 5 -and ($partialCount + $rejectCount) -ge [math]::Ceiling($roundCount * 0.6)) {
  $efficiency = '可能低效循环'
} elseif ($reworkCount -ge 2) {
  $efficiency = '返工偏多'
} elseif ($verificationCount -eq 0 -and $roundCount -gt 0) {
  $efficiency = '缺少验证证据'
}

$drift = '未发现明显偏移'
if ($driftWarnings.Count -gt 0) {
  $drift = '可能偏移'
} elseif ([string]::IsNullOrWhiteSpace($goalText)) {
  $drift = '没有明确目标，无法判断'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$mdPath = Join-Path $OutDir "workloop-summary-$pairId-$stamp.md"
$htmlPath = Join-Path $OutDir "workloop-summary-$pairId-$stamp.html"

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
if ($overall -eq '目标已完成' -or $overall -eq '最近一轮已接受，可能已完成') {
  [void]$md.AppendLine("- 可以先停止这个 pair，必要时生成完整复盘或审计。")
} elseif ($efficiency -eq '可能低效循环' -or $efficiency -eq '返工偏多') {
  [void]$md.AppendLine("- 建议暂停继续执行，让 Codex 或人工重新收敛目标和验收标准。")
} elseif ($drift -eq '可能偏移') {
  [void]$md.AppendLine("- 建议先更新目标或重新规划任务，再让 CC 继续。")
} else {
  [void]$md.AppendLine("- 可以继续下一轮，但下一条任务应该保持单一目标和明确验收。")
}

$localMdText = $md.ToString()
$mdText = $localMdText
$encoding = [System.Text.UTF8Encoding]::new($true)

if ($Analyzer -ne 'local') {
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
8. 必须使用下面的六个二级标题，不要换成表格式问答。

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

if ($Format -eq 'md' -or $Format -eq 'both') {
  [System.IO.File]::WriteAllText($mdPath, $mdText, $encoding)
  [System.IO.File]::WriteAllText($latestMdPath, $mdText, $encoding)
}

if ($Format -eq 'html' -or $Format -eq 'both') {
  $html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>Pair 会话总结 - $pairId</title>
  <style>
    body { margin: 0; background: #f7f7f4; color: #1f2933; font-family: "Segoe UI", "Microsoft YaHei", Arial, sans-serif; line-height: 1.62; }
    main { max-width: 1040px; margin: 0 auto; background: #fff; min-height: 100vh; padding: 28px 34px 60px; }
    h1 { margin: 0 0 12px; font-size: 30px; }
    h2 { margin-top: 30px; border-top: 1px solid #d8ddd8; padding-top: 22px; }
    h3 { margin-top: 22px; color: #374151; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; background: #f5f6f2; border: 1px solid #e4e6df; border-radius: 8px; padding: 16px; }
    code { background: #f5f6f2; border-radius: 4px; padding: 2px 5px; }
  </style>
</head>
<body><main><pre>$(Encode-Html $mdText)</pre></main></body>
</html>
"@
  [System.IO.File]::WriteAllText($htmlPath, $html, $encoding)
  [System.IO.File]::WriteAllText($latestHtmlPath, $html, $encoding)
}

Write-AiRelayJson ([ordered]@{
  pairId = $pairId
  projectRoot = $projectRoot
  analyzer = $Analyzer
  sourceHash = $sourceHash
  generatedAt = (Get-Date).ToString('o')
  markdown = $mdPath
  html = $htmlPath
  latestMarkdown = $latestMdPath
  latestHtml = $latestHtmlPath
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
