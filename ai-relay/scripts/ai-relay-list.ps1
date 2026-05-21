$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

$projectRoot = Get-AiRelayProjectRoot
$pairsRoot = Join-Path (Get-AiRelayRoot $projectRoot) 'pairs'
if (-not (Test-Path -LiteralPath $pairsRoot)) {
  Write-Host "当前项目没有 .ai-relay/pairs/。请先运行 /bind <pair>。"
  exit 0
}
$dirs = Get-ChildItem -LiteralPath $pairsRoot -Directory -ErrorAction SilentlyContinue
if (-not $dirs) {
  Write-Host "当前项目还没有 pair。请先运行 /bind <pair>。"
  exit 0
}
& {
foreach ($dir in $dirs) {
  $pairJsonPath = Join-Path $dir.FullName 'pair.json'
  if (Test-Path -LiteralPath $pairJsonPath) {
    $p = Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
    [pscustomobject]@{
      pairId = $p.pairId
      task = $p.task
      role = $p.role
      codexSessionId = $p.codexSessionId
      ccSessionName = $p.ccSessionName
      boundAt = $p.boundAt
      'pair path' = $dir.FullName
    }
  } else {
    [pscustomobject]@{
      pairId = $dir.Name
      task = ''
      role = ''
      codexSessionId = ''
      ccSessionName = ''
      boundAt = ''
      'pair path' = $dir.FullName
    }
  }
}
} | Format-Table -AutoSize