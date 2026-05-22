param(
  [string]$Pair,
  [string]$Message,
  [string]$FromFile,
  [switch]$ShowReport,
  [switch]$ShowPrompt,
  [switch]$ShowReply,
  [switch]$History,
  [string]$HistoryId
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

$projectRoot = Get-AiRelayProjectRoot
$pairId = Get-AiRelayPairId -ProjectRoot $projectRoot -Pair $Pair
Assert-AiRelayPairName $pairId
$pairDir = Get-AiRelayPairDir $projectRoot $pairId
[void](Read-AiRelayPairJson $pairDir)

if ($History) {
  $historyRoot = Join-Path $pairDir 'history'
  if (-not (Test-Path -LiteralPath $historyRoot)) {
    Write-Output "No history found for pair '$pairId'."
    exit 0
  }
  Get-ChildItem -LiteralPath $historyRoot -Directory |
    Sort-Object Name -Descending |
    ForEach-Object {
      $summaryPath = Join-Path $_.FullName 'summary.json'
      if (Test-Path -LiteralPath $summaryPath) {
        $s = Get-Content -LiteralPath $summaryPath -Raw -Encoding utf8 | ConvertFrom-Json
        [pscustomobject]@{
          id = $_.Name
          createdAt = $s.createdAt
          codexSessionId = $s.codexSessionId
          reportBytes = $s.reportBytes
          promptBytes = $s.promptBytes
          replyBytes = $s.replyBytes
          path = $_.FullName
        }
      } else {
        [pscustomobject]@{
          id = $_.Name
          createdAt = ''
          codexSessionId = ''
          reportBytes = ''
          promptBytes = ''
          replyBytes = ''
          path = $_.FullName
        }
      }
    } | Format-Table -AutoSize
  exit 0
}

if ($HistoryId) {
  $historyDir = Join-Path (Join-Path $pairDir 'history') $HistoryId
  if (-not (Test-Path -LiteralPath $historyDir)) {
    throw "History item not found: $historyDir"
  }
  if (-not ($ShowReport -or $ShowPrompt -or $ShowReply)) {
    $ShowReport = $true
    $ShowPrompt = $true
    $ShowReply = $true
  }
  $readBaseDir = $historyDir
} else {
  $readBaseDir = $pairDir
}

if ($ShowReport -or $ShowPrompt -or $ShowReply) {
  $items = @()
  if ($ShowReport) { $items += @{ Title = 'cc-report.md'; Path = (Join-Path $readBaseDir 'cc-report.md') } }
  if ($ShowPrompt) { $items += @{ Title = 'codex-prompt.md'; Path = (Join-Path $readBaseDir 'codex-prompt.md') } }
  if ($ShowReply) { $items += @{ Title = 'codex-reply.md'; Path = (Join-Path $readBaseDir 'codex-reply.md') } }
  foreach ($item in $items) {
    Write-Output ""
    Write-Output "===== $($item.Title) ====="
    if (Test-Path -LiteralPath $item.Path) {
      $content = Get-Content -LiteralPath $item.Path -Raw -Encoding utf8
      if ([string]::IsNullOrWhiteSpace($content)) {
        Write-Output "(empty)"
      } else {
        Write-Output $content
      }
    } else {
      Write-Output "(missing: $($item.Path))"
    }
  }
  exit 0
}

if ($Message -and $FromFile) {
  throw "Use either -Message or -FromFile, not both."
}
if ($FromFile) {
  if (-not (Test-Path -LiteralPath $FromFile)) { throw "FromFile not found: $FromFile" }
  $content = Get-Content -LiteralPath $FromFile -Raw -Encoding utf8
} elseif ($Message) {
  $content = $Message
} else {
  Write-Host "请提供 -Message 或 -FromFile。Codex Skill 可基于当前上下文生成给 Claude Code 的下一步指令后再调用本命令。"
  exit 1
}

$inboxPath = Join-Path $pairDir 'cc-inbox.md'
$payload = @"
# Codex -> Claude Code

pairId: $pairId
createdAt: $(Get-Date -Format o)

## 下一轮最小任务指令

$content
"@
Set-Content -LiteralPath $inboxPath -Value $payload -Encoding utf8
Add-AiRelayLog -PairDir $pairDir -Event 'codex-to-cc' -Detail $content
[void](Copy-AiRelayText $payload)

Write-Host "已写入 cc-inbox.md，请在对应 Claude Code 会话中执行 /workloop <pair>，或直接粘贴剪贴板内容。"
Write-Host "Inbox: $inboxPath"
