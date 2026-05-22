param(
  [Parameter(Mandatory=$true)][string]$Pair,
  [Parameter(Mandatory=$true)][string]$CodexSessionId,
  [string]$Role = 'commander',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

Assert-AiRelayPairName $Pair
$projectRoot = Get-AiRelayProjectRoot
$pairDir = Get-AiRelayPairDir $projectRoot $Pair
$bindPath = Join-Path $pairDir 'bind-request.md'
$pairJsonPath = Join-Path $pairDir 'pair.json'

if (-not (Test-Path -LiteralPath $bindPath)) {
  throw "bind-request.md not found: $bindPath. Run ai-relay-bind-cc.ps1 -Pair $Pair from Claude Code first."
}
if ((Test-Path -LiteralPath $pairJsonPath) -and -not $Force) {
  $existing = Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
  if ($existing.codexSessionId -and $existing.codexSessionId -ne $CodexSessionId) {
    throw "Pair '$Pair' is already bound to another Codex session. Use -Force only if you intentionally want to rebind it."
  }
}

$bindText = Get-Content -LiteralPath $bindPath -Raw -Encoding utf8
function Get-BindValue([string]$Name) {
  $m = [regex]::Match($bindText, "(?m)^$([regex]::Escape($Name)):[ \t]*(.*)$")
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  ''
}

$task = Get-BindValue 'task'
$ccSessionId = Get-BindValue 'ccSessionId'
$ccSessionName = Get-BindValue 'ccSessionName'
$ccInboxPath = Get-BindValue 'ccInboxPath'
$ccReportPath = Get-BindValue 'ccReportPath'
$codexReplyPath = Get-BindValue 'codexReplyPath'

$pairJson = [ordered]@{
  pairId = $Pair
  projectRoot = $projectRoot
  task = $task
  codexSessionId = $CodexSessionId
  ccSessionId = $ccSessionId
  ccSessionName = $ccSessionName
  ccInboxPath = $ccInboxPath
  ccReportPath = $ccReportPath
  codexReplyPath = $codexReplyPath
  role = $Role
  boundAt = (Get-Date).ToString('o')
}
Write-AiRelayJson $pairJson $pairJsonPath

$context = @"
# AI Relay Pair Context

你是当前项目中此 pair 的 Codex 指挥线程。
Claude Code 是此 pair 的执行工程师。
只处理当前 pair 的任务。
不使用 subagent。
不启动 codex-with-cc。
不使用 --last。
Codex 只做验收、裁决、风险判断、下一轮最小任务指令。
不要要求 Claude Code 返回大段日志。
不要把完整项目代码塞进 prompt。
如果可能与其他 pair 冲突，必须提醒。

pairId: $Pair
projectRoot: $projectRoot
task: $task
codexSessionId: $CodexSessionId
ccSessionId: $ccSessionId
ccSessionName: $ccSessionName
"@
Set-Content -LiteralPath (Join-Path $pairDir 'context.md') -Value $context -Encoding utf8
Set-AiRelayCurrentPair -ProjectRoot $projectRoot -Pair $Pair -Task $task
Add-AiRelayLog -PairDir $pairDir -Event 'bind-codex' -Detail "Bound Codex session id $CodexSessionId."

Write-Host "绑定完成：$Pair"
Write-Host "Codex session id: $CodexSessionId"
Write-Host "Pair path: $pairDir"
