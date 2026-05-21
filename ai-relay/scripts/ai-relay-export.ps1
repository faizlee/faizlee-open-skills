param(
  [string]$Pair,
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
  return "(missing: $Path)"
}

function Get-RelayFileInfo {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $item = Get-Item -LiteralPath $Path
    return "$($item.Length) bytes, last write $($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
  }
  return "missing"
}

function Add-MdSection {
  param(
    [System.Text.StringBuilder]$Builder,
    [string]$Title,
    [string]$Path,
    [string]$Language = 'text'
  )
  [void]$Builder.AppendLine("")
  [void]$Builder.AppendLine("## $Title")
  [void]$Builder.AppendLine("")
  [void]$Builder.AppendLine('Path: `' + $Path + '`')
  [void]$Builder.AppendLine("")
  [void]$Builder.AppendLine("Info: $(Get-RelayFileInfo $Path)")
  [void]$Builder.AppendLine("")
  [void]$Builder.AppendLine("````$Language")
  [void]$Builder.AppendLine((Read-RelayFile $Path))
  [void]$Builder.AppendLine("````")
}

function Encode-Html {
  param([string]$Text)
  [System.Net.WebUtility]::HtmlEncode($Text)
}

$projectRoot = Get-AiRelayProjectRoot
$pairId = Get-AiRelayPairId -ProjectRoot $projectRoot -Pair $Pair
Assert-AiRelayPairName $pairId
$pairDir = Get-AiRelayPairDir $projectRoot $pairId
if (-not (Test-Path -LiteralPath $pairDir)) {
  throw "Pair not found: $pairDir"
}

if (-not $OutDir) {
  $OutDir = Join-Path $pairDir 'exports'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$baseName = "ai-relay-$pairId-$stamp"
$mdPath = Join-Path $OutDir "$baseName.md"
$htmlPath = Join-Path $OutDir "$baseName.html"

$pairJsonPath = Join-Path $pairDir 'pair.json'
$bindPath = Join-Path $pairDir 'bind-request.md'
$contextPath = Join-Path $pairDir 'context.md'
$inboxPath = Join-Path $pairDir 'cc-inbox.md'
$inboxReadPath = Join-Path $pairDir 'cc-inbox.read.md'
$reportPath = Join-Path $pairDir 'cc-report.md'
$promptPath = Join-Path $pairDir 'codex-prompt.md'
$replyPath = Join-Path $pairDir 'codex-reply.md'
$logPath = Join-Path $pairDir 'relay-log.md'
$historyRoot = Join-Path $pairDir 'history'

$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine("# AI Relay 会话审计报告")
[void]$md.AppendLine("")
[void]$md.AppendLine('- Pair: `' + $pairId + '`')
[void]$md.AppendLine('- 项目目录: `' + $projectRoot + '`')
[void]$md.AppendLine('- Pair 目录: `' + $pairDir + '`')
[void]$md.AppendLine("- 导出时间: $(Get-Date -Format o)")
[void]$md.AppendLine("")
[void]$md.AppendLine("## 如何阅读这份报告")
[void]$md.AppendLine("")
[void]$md.AppendLine('- `cc-inbox.md` 是 Codex 最新发给 Claude Code 的任务指令。')
[void]$md.AppendLine('- `cc-report.md` 是 Claude Code 写给 Codex 的压缩报告。')
[void]$md.AppendLine('- `codex-prompt.md` 是 report 模式实际发送给 Codex 的完整 prompt，通常只包含 context.md、cc-report.md 和固定输出格式要求。')
[void]$md.AppendLine('- `codex-reply.md` 是 Codex 后台调用写出的最新回复。')
[void]$md.AppendLine('- 当前 V1 的最新文件会被后续 relay 覆盖；如果没有历史归档，旧轮次无法完整恢复。')

Add-MdSection $md '一、Pair 绑定信息' $pairJsonPath 'json'
Add-MdSection $md '二、绑定请求原文' $bindPath 'markdown'
Add-MdSection $md '三、Pair 上下文规则' $contextPath 'markdown'
Add-MdSection $md '四、Codex 发给 Claude Code 的最新指令' $inboxPath 'markdown'
Add-MdSection $md '五、Claude Code 已读标记' $inboxReadPath 'markdown'
Add-MdSection $md '六、Claude Code 最新汇报' $reportPath 'markdown'
Add-MdSection $md '七、实际发送给 Codex 的完整 Prompt' $promptPath 'markdown'
Add-MdSection $md '八、Codex 最新回复' $replyPath 'markdown'
Add-MdSection $md '九、Relay 时间线' $logPath 'markdown'

[void]$md.AppendLine("")
[void]$md.AppendLine("## 十、历史归档")
[void]$md.AppendLine("")
if (Test-Path -LiteralPath $historyRoot) {
  $historyDirs = Get-ChildItem -LiteralPath $historyRoot -Directory | Sort-Object Name
  if ($historyDirs) {
    foreach ($history in $historyDirs) {
      [void]$md.AppendLine("")
      [void]$md.AppendLine("### 历史轮次 $($history.Name)")
      [void]$md.AppendLine("")
      $summaryPath = Join-Path $history.FullName 'summary.json'
      [void]$md.AppendLine("#### summary.json")
      [void]$md.AppendLine("")
      [void]$md.AppendLine("````json")
      [void]$md.AppendLine((Read-RelayFile $summaryPath))
      [void]$md.AppendLine("````")
      foreach ($fileName in @('cc-report.md','codex-prompt.md','codex-reply.md')) {
        $path = Join-Path $history.FullName $fileName
        [void]$md.AppendLine("")
        [void]$md.AppendLine("#### $fileName")
        [void]$md.AppendLine("")
        [void]$md.AppendLine("````markdown")
        [void]$md.AppendLine((Read-RelayFile $path))
        [void]$md.AppendLine("````")
      }
    }
  } else {
    [void]$md.AppendLine("当前还没有历史轮次。")
  }
} else {
  [void]$md.AppendLine("当前还没有历史归档目录。")
}

$mdText = $md.ToString()
if ($Format -eq 'md' -or $Format -eq 'both') {
  $encoding = [System.Text.UTF8Encoding]::new($true)
  [System.IO.File]::WriteAllText($mdPath, $mdText, $encoding)
}

if ($Format -eq 'html' -or $Format -eq 'both') {
  $htmlSections = @(
    @{ Title = '一、Pair 绑定信息'; Path = $pairJsonPath },
    @{ Title = '二、绑定请求原文'; Path = $bindPath },
    @{ Title = '三、Pair 上下文规则'; Path = $contextPath },
    @{ Title = '四、Codex 发给 Claude Code 的最新指令'; Path = $inboxPath },
    @{ Title = '五、Claude Code 已读标记'; Path = $inboxReadPath },
    @{ Title = '六、Claude Code 最新汇报'; Path = $reportPath },
    @{ Title = '七、实际发送给 Codex 的完整 Prompt'; Path = $promptPath },
    @{ Title = '八、Codex 最新回复'; Path = $replyPath },
    @{ Title = '九、Relay 时间线'; Path = $logPath }
  )
  $body = [System.Text.StringBuilder]::new()
  foreach ($section in $htmlSections) {
    [void]$body.AppendLine("<section>")
    [void]$body.AppendLine("<h2>$(Encode-Html ($section.Title))</h2>")
    [void]$body.AppendLine("<p><code>$(Encode-Html ($section.Path))</code></p>")
    [void]$body.AppendLine("<p class=""meta"">$(Encode-Html (Get-RelayFileInfo ($section.Path)))</p>")
    [void]$body.AppendLine("<pre>$(Encode-Html (Read-RelayFile ($section.Path)))</pre>")
    [void]$body.AppendLine("</section>")
  }
  [void]$body.AppendLine("<section>")
  [void]$body.AppendLine("<h2>十、历史归档</h2>")
  if (Test-Path -LiteralPath $historyRoot) {
    $historyDirs = Get-ChildItem -LiteralPath $historyRoot -Directory | Sort-Object Name
    if ($historyDirs) {
      foreach ($history in $historyDirs) {
        [void]$body.AppendLine("<details>")
        [void]$body.AppendLine("<summary>历史轮次 $(Encode-Html ($history.Name))</summary>")
        $summaryPath = Join-Path $history.FullName 'summary.json'
        [void]$body.AppendLine("<h3>summary.json</h3>")
        [void]$body.AppendLine("<pre>$(Encode-Html (Read-RelayFile $summaryPath))</pre>")
        foreach ($fileName in @('cc-report.md','codex-prompt.md','codex-reply.md')) {
          $path = Join-Path $history.FullName $fileName
          [void]$body.AppendLine("<h3>$(Encode-Html $fileName)</h3>")
          [void]$body.AppendLine("<pre>$(Encode-Html (Read-RelayFile $path))</pre>")
        }
        [void]$body.AppendLine("</details>")
      }
    } else {
      [void]$body.AppendLine("<p>当前还没有历史轮次。</p>")
    }
  } else {
    [void]$body.AppendLine("<p>当前还没有历史归档目录。</p>")
  }
  [void]$body.AppendLine("</section>")
  $html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>AI Relay 会话审计报告 - $pairId</title>
  <style>
    body { font-family: "Segoe UI", "Microsoft YaHei", Arial, sans-serif; margin: 0; color: #1f2328; line-height: 1.55; background: #f6f8fa; }
    main { max-width: 1180px; margin: 0 auto; padding: 32px 28px 56px; background: #ffffff; min-height: 100vh; }
    h1 { margin: 0 0 8px; font-size: 28px; }
    h2 { border-top: 1px solid #d0d7de; padding-top: 22px; margin-top: 30px; font-size: 20px; }
    code { background: #f6f8fa; padding: 2px 5px; border-radius: 4px; }
    pre { background: #0d1117; color: #e6edf3; border: 1px solid #30363d; border-radius: 6px; padding: 14px; overflow: auto; white-space: pre-wrap; word-break: break-word; }
    .meta { color: #57606a; font-size: 13px; }
    .notice { background: #fff8c5; border: 1px solid #eac54f; border-radius: 6px; padding: 12px 14px; }
  </style>
</head>
<body>
<main>
  <h1>AI Relay 会话审计报告</h1>
  <p class="meta">Pair: <code>$(Encode-Html $pairId)</code> | 导出时间: $(Get-Date -Format o)</p>
  <p>项目目录：<code>$(Encode-Html $projectRoot)</code></p>
  <p>Pair 目录：<code>$(Encode-Html $pairDir)</code></p>
  <section>
    <h2>如何阅读这份报告</h2>
    <div class="notice">
      这份报告汇总当前 pair 仍保留的最新 relay 文件。重点看“Claude Code 最新汇报”、“实际发送给 Codex 的完整 Prompt”和“Codex 最新回复”。
      当前 V1 的最新文件会被后续 relay 覆盖；如果没有历史归档，旧轮次无法完整恢复。
    </div>
  </section>
  $($body.ToString())
</main>
</body>
</html>
"@
  $encoding = [System.Text.UTF8Encoding]::new($true)
  [System.IO.File]::WriteAllText($htmlPath, $html, $encoding)
}

Write-Host "AI Relay export generated:"
if ($Format -eq 'md' -or $Format -eq 'both') { Write-Host "Markdown: $mdPath" }
if ($Format -eq 'html' -or $Format -eq 'both') { Write-Host "HTML: $htmlPath" }
if ($Open) {
  if ($Format -eq 'md') {
    Invoke-Item -LiteralPath $mdPath
  } else {
    Invoke-Item -LiteralPath $htmlPath
  }
}