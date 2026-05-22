param(
  [Parameter(Mandatory=$true)][string]$Pair,
  [string]$CcSessionId = '',
  [string]$Task = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

function Set-ObjectProperty {
  param(
    [Parameter(Mandatory=$true)]$Object,
    [Parameter(Mandatory=$true)][string]$Name,
    $Value
  )
  $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

Assert-AiRelayPairName $Pair
$projectRoot = Get-AiRelayProjectRoot
$pairDir = Get-AiRelayPairDir $projectRoot $Pair

if (-not (Test-Path -LiteralPath $pairDir)) {
  throw "Pair '$Pair' does not exist in this project. Run /bind $Pair first, or switch to the project root that contains .ai-relay\pairs\$Pair."
}

$detectedCcSessionId = if ($CcSessionId) {
  $CcSessionId
} elseif ($env:CLAUDE_SESSION_ID) {
  $env:CLAUDE_SESSION_ID
} elseif ($env:CLAUDE_CODE_SESSION_ID) {
  $env:CLAUDE_CODE_SESSION_ID
} else {
  ''
}

if (-not $detectedCcSessionId) {
  throw "Could not detect Claude Code session id. Run Claude Code /status to find it, then run: ai-workloop-rebind-cc.ps1 -Pair $Pair -CcSessionId <Claude Code session id>"
}

$pairJsonPath = Join-Path $pairDir 'pair.json'
$pairJson = $null
if (Test-Path -LiteralPath $pairJsonPath) {
  $pairJson = Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
}

if (-not $Task -and $pairJson -and $pairJson.task) {
  $Task = [string]$pairJson.task
}

$ccSessionName = if ($detectedCcSessionId) {
  $detectedCcSessionId
} elseif ($env:WT_SESSION) {
  "WT:$($env:WT_SESSION)"
} else {
  "$env:USERNAME@$env:COMPUTERNAME"
}

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
  if (-not (Test-Path -LiteralPath $path)) {
    Set-Content -LiteralPath $path -Value $files[$name] -Encoding utf8
  }
}

$ccInboxPath = Join-Path $pairDir 'cc-inbox.md'
$ccReportPath = Join-Path $pairDir 'cc-report.md'
$codexReplyPath = Join-Path $pairDir 'codex-reply.md'
$createdAt = (Get-Date).ToString('o')

$bindRequest = @"
# AI Relay Bind Request

pairId: $Pair
projectRoot: $projectRoot
task: $Task
ccSessionId: $detectedCcSessionId
ccSessionName: $ccSessionName
ccInboxPath: $ccInboxPath
ccReportPath: $ccReportPath
codexReplyPath: $codexReplyPath
createdAt: $createdAt
rebind: true

## Bind Notes

This is a Claude Code side rebind request for an existing pair.

If pair.json already exists, this script only updates Claude Code metadata and preserves codexSessionId, reports, replies, and logs.

If Codex context needs to be refreshed, run this in the matching Codex session:

ai-relay-bind-codex.ps1 -Pair $Pair -CodexSessionId "<current Codex session id>" -Force

Rules:
- One pair binds one explicit Codex session id.
- One pair binds one explicit Claude Code session id.
- Do not use --last.
- Do not use subagent.
- Do not start codex-with-cc.
"@

$bindPath = Join-Path $pairDir 'bind-request.md'
Set-Content -LiteralPath $bindPath -Value $bindRequest -Encoding utf8

if ($pairJson) {
  Set-ObjectProperty -Object $pairJson -Name 'ccSessionId' -Value $detectedCcSessionId
  Set-ObjectProperty -Object $pairJson -Name 'ccSessionName' -Value $ccSessionName
  Set-ObjectProperty -Object $pairJson -Name 'ccInboxPath' -Value $ccInboxPath
  Set-ObjectProperty -Object $pairJson -Name 'ccReportPath' -Value $ccReportPath
  Set-ObjectProperty -Object $pairJson -Name 'codexReplyPath' -Value $codexReplyPath
  if (-not $pairJson.task -and $Task) {
    Set-ObjectProperty -Object $pairJson -Name 'task' -Value $Task
  }
  Set-ObjectProperty -Object $pairJson -Name 'ccReboundAt' -Value $createdAt
  Write-AiRelayJson $pairJson $pairJsonPath
}

Set-AiRelayCurrentPair -ProjectRoot $projectRoot -Pair $Pair -Task $Task
Add-AiRelayLog -PairDir $pairDir -Event 'cc-rebind' -Detail "Updated Claude Code session id for this pair. ccSessionId=$detectedCcSessionId"
[void](Copy-AiRelayText $bindRequest)

Write-Host "Claude Code binding metadata refreshed."
Write-Host "Pair: $Pair"
Write-Host "ccSessionId: $detectedCcSessionId"
Write-Host "Bind request: $bindPath"
if ($pairJson) {
  Write-Host "pair.json updated. Existing codexSessionId, reports, replies, and logs were preserved."
} else {
  Write-Host "pair.json does not exist yet. Send bind-request.md to Codex and run /bind $Pair."
}
