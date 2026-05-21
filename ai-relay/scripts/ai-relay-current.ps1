$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

$projectRoot = Get-AiRelayProjectRoot
$currentPath = Join-Path (Get-AiRelayRoot $projectRoot) 'current-pair.json'
if (-not (Test-Path -LiteralPath $currentPath)) {
  Write-Host "当前项目还没有默认 pair。请先运行 /bind <pair> 或 ai-relay-use.ps1 -Pair <pair>。"
  exit 0
}
$current = Get-Content -LiteralPath $currentPath -Raw -Encoding utf8 | ConvertFrom-Json
Write-Host "pairId: $($current.pairId)"
Write-Host "task: $($current.task)"
Write-Host "projectRoot: $($current.projectRoot)"