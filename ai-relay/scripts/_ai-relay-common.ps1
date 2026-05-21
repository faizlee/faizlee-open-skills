function Get-AiRelayProjectRoot {
  (Get-Location).ProviderPath
}

function Get-AiRelayRoot {
  param([string]$ProjectRoot)
  Join-Path $ProjectRoot '.ai-relay'
}

function Assert-AiRelayPairName {
  param([Parameter(Mandatory=$true)][string]$Pair)
  if ($Pair -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Invalid pair name '$Pair'. Use letters, digits, dot, underscore, or dash; it must start with a letter or digit."
  }
}

function Get-AiRelayPairId {
  param([string]$ProjectRoot, [string]$Pair)
  if ($Pair) { return $Pair }
  $currentPath = Join-Path (Get-AiRelayRoot $ProjectRoot) 'current-pair.json'
  if (-not (Test-Path -LiteralPath $currentPath)) {
    throw "No current pair. Run /bind <pair> or ai-relay-use.ps1 -Pair <pair> first."
  }
  $current = Get-Content -LiteralPath $currentPath -Raw -Encoding utf8 | ConvertFrom-Json
  if (-not $current.pairId) {
    throw "current-pair.json does not contain pairId. Run ai-relay-use.ps1 -Pair <pair>."
  }
  $current.pairId
}

function Get-AiRelayPairDir {
  param([string]$ProjectRoot, [string]$Pair)
  Join-Path (Join-Path (Get-AiRelayRoot $ProjectRoot) 'pairs') $Pair
}

function Read-AiRelayPairJson {
  param([string]$PairDir)
  $pairJsonPath = Join-Path $PairDir 'pair.json'
  if (-not (Test-Path -LiteralPath $pairJsonPath)) {
    throw "pair.json not found: $pairJsonPath. Bind this pair from Codex first."
  }
  Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
}

function Write-AiRelayJson {
  param([Parameter(Mandatory=$true)]$Object, [Parameter(Mandatory=$true)][string]$Path)
  $Object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Set-AiRelayCurrentPair {
  param([string]$ProjectRoot, [string]$Pair, [string]$Task)
  $root = Get-AiRelayRoot $ProjectRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    task = $Task
    projectRoot = $ProjectRoot
    updatedAt = (Get-Date).ToString('o')
  }) (Join-Path $root 'current-pair.json')
}

function Add-AiRelayLog {
  param([string]$PairDir, [string]$Event, [string]$Detail)
  $logPath = Join-Path $PairDir 'relay-log.md'
  $entry = @"

## $(Get-Date -Format o) - $Event
$Detail
"@
  Add-Content -LiteralPath $logPath -Value $entry -Encoding utf8
}

function Copy-AiRelayText {
  param([string]$Text)
  try {
    Set-Clipboard -Value $Text
    return $true
  } catch {
    Write-Warning "Failed to copy to clipboard: $($_.Exception.Message)"
    return $false
  }
}

function Read-AiRelayTextFile {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    return (Get-Content -LiteralPath $Path -Raw -Encoding utf8)
  }
  ''
}