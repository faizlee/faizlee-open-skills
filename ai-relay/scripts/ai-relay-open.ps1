param(
  [string]$Pair
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

$projectRoot = Get-AiRelayProjectRoot
$pairId = Get-AiRelayPairId -ProjectRoot $projectRoot -Pair $Pair
Assert-AiRelayPairName $pairId
$pairDir = Get-AiRelayPairDir $projectRoot $pairId
if (-not (Test-Path -LiteralPath $pairDir)) {
  throw "Pair '$pairId' does not exist: $pairDir"
}
Start-Process explorer.exe -ArgumentList "`"$pairDir`""
Write-Host "Opened: $pairDir"