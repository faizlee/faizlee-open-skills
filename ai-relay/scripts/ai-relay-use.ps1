param(
  [Parameter(Mandatory=$true)][string]$Pair
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

Assert-AiRelayPairName $Pair
$projectRoot = Get-AiRelayProjectRoot
$pairDir = Get-AiRelayPairDir $projectRoot $Pair
if (-not (Test-Path -LiteralPath $pairDir)) {
  throw "Pair '$Pair' does not exist in this project: $pairDir"
}
$task = ''
$pairJsonPath = Join-Path $pairDir 'pair.json'
if (Test-Path -LiteralPath $pairJsonPath) {
  $pairJson = Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
  $task = [string]$pairJson.task
}
Set-AiRelayCurrentPair -ProjectRoot $projectRoot -Pair $Pair -Task $task
Write-Host "当前默认 pair: $Pair"