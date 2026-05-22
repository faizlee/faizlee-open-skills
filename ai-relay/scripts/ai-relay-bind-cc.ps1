param(
  [Parameter(Mandatory=$true)][string]$Pair,
  [string]$Task = '',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

Assert-AiRelayPairName $Pair
$projectRoot = Get-AiRelayProjectRoot
$pairDir = Get-AiRelayPairDir $projectRoot $Pair

if ((Test-Path -LiteralPath $pairDir) -and -not $Force) {
  throw "Pair '$Pair' already exists. Use -Force only if you intentionally want to refresh generated files for this pair."
}

New-Item -ItemType Directory -Force -Path $pairDir | Out-Null

$files = @{
  'context.md' = "# AI Relay Context`n`nPending Codex bind.`n"
  'cc-inbox.md' = ''
  'cc-inbox.read.md' = ''
  'cc-report.md' = "# CC Report`n`n## 当前任务`n`n## Claude Code 本轮做了什么`n`n## 修改文件`n`n## 验证结果`n`n## 风险 / 疑问`n`n## 是否可能与其他 pair 冲突`n`n## 需要 Codex 裁决的问题`n"
  'codex-prompt.md' = ''
  'codex-reply.md' = ''
  'codex-reply.read.md' = ''
  'relay-log.md' = "# AI Relay Log`n"
}

foreach ($name in $files.Keys) {
  $path = Join-Path $pairDir $name
  if ($Force -or -not (Test-Path -LiteralPath $path)) {
    Set-Content -LiteralPath $path -Value $files[$name] -Encoding utf8
  }
}

$ccSessionName = if ($env:CLAUDE_SESSION_ID) { $env:CLAUDE_SESSION_ID } elseif ($env:WT_SESSION) { "WT:$($env:WT_SESSION)" } else { "$env:USERNAME@$env:COMPUTERNAME" }
$createdAt = (Get-Date).ToString('o')
$ccInboxPath = Join-Path $pairDir 'cc-inbox.md'
$ccReportPath = Join-Path $pairDir 'cc-report.md'
$codexReplyPath = Join-Path $pairDir 'codex-reply.md'
$bindRequest = @"
# AI Relay Bind Request

pairId: $Pair
projectRoot: $projectRoot
task: $Task
ccSessionName: $ccSessionName
ccInboxPath: $ccInboxPath
ccReportPath: $ccReportPath
codexReplyPath: $codexReplyPath
createdAt: $createdAt

## 绑定说明

请把这份 bind-request.md 粘贴到对应 Codex 会话，然后在 Codex 中执行：

ai-relay-bind-codex.ps1 -Pair $Pair -CodexSessionId "<当前Codex session id>"

规则：
- 一个 pair 绑定一个明确的 Codex session id。
- 不使用 --last。
- 不使用 subagent。
- 不启动 codex-with-cc。
"@

$bindPath = Join-Path $pairDir 'bind-request.md'
Set-Content -LiteralPath $bindPath -Value $bindRequest -Encoding utf8
Set-AiRelayCurrentPair -ProjectRoot $projectRoot -Pair $Pair -Task $Task
Add-AiRelayLog -PairDir $pairDir -Event 'bind-request' -Detail "Created bind request from Claude Code side."
[void](Copy-AiRelayText $bindRequest)

Write-Host "已生成绑定请求，请把剪贴板内容粘贴到对应 Codex 会话，然后在 Codex 中执行 /bind $Pair。"
Write-Host "Bind request: $bindPath"
