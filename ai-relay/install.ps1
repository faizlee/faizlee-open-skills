param(
  [switch]$SkipPathUpdate
)

$ErrorActionPreference = 'Stop'

$sourceRoot = $PSScriptRoot
$scriptsSource = Join-Path $sourceRoot 'scripts'
$skillsSource = Join-Path $sourceRoot 'skills'
$commandsSource = Join-Path $sourceRoot 'commands'

$toolRoot = Join-Path $HOME '.ai-tools\ai-relay'
$binRoot = Join-Path $HOME '.ai-tools\bin'

function Copy-Tree {
  param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
  )
  if (-not (Test-Path -LiteralPath $Source)) {
    throw "Source path not found: $Source"
  }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
  }
}

function Copy-IfExists {
  param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
  )
  if (Test-Path -LiteralPath $Source) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
  }
}

function Convert-Ps1ToUtf8Bom {
  param([Parameter(Mandatory=$true)][string]$Path)
  $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
  $encoding = [System.Text.UTF8Encoding]::new($true)
  [System.IO.File]::WriteAllText($Path, $content, $encoding)
}

New-Item -ItemType Directory -Force -Path $toolRoot, $binRoot | Out-Null

Copy-Tree -Source $scriptsSource -Destination $binRoot
Get-ChildItem -LiteralPath $binRoot -Filter '*.ps1' -File | ForEach-Object {
  Convert-Ps1ToUtf8Bom -Path $_.FullName
}
Copy-Tree -Source $skillsSource -Destination (Join-Path $toolRoot 'skills')
Copy-Tree -Source $commandsSource -Destination (Join-Path $toolRoot 'commands')
$oldGoalCommand = Join-Path $toolRoot 'commands\goal.md'
if (Test-Path -LiteralPath $oldGoalCommand) {
  Remove-Item -LiteralPath $oldGoalCommand -Force
}
Copy-IfExists -Source (Join-Path $sourceRoot 'README.md') -Destination (Join-Path $toolRoot 'README.md')
Copy-IfExists -Source (Join-Path $sourceRoot 'README.zh-CN.md') -Destination (Join-Path $toolRoot 'README.zh-CN.md')

& (Join-Path $binRoot 'ai-relay-init-skill.ps1')

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries = @()
if ($userPath) {
  $pathEntries = $userPath -split ';' | Where-Object { $_ }
}
$hasUserPath = ($pathEntries | Where-Object { $_.TrimEnd('\') -ieq $binRoot.TrimEnd('\') } | Measure-Object).Count -gt 0
$hasProcessPath = (($env:Path -split ';') | Where-Object { $_.TrimEnd('\') -ieq $binRoot.TrimEnd('\') } | Measure-Object).Count -gt 0
$pathAdded = $false

if (-not $hasUserPath -and -not $SkipPathUpdate) {
  $newUserPath = if ($pathEntries) { ($pathEntries + $binRoot) -join ';' } else { $binRoot }
  [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
  $pathAdded = $true
}

if (-not $hasProcessPath) {
  $env:Path = "$binRoot;$env:Path"
}

[pscustomobject]@{
  SourceRoot = $sourceRoot
  ToolRoot = $toolRoot
  Bin = $binRoot
  PathAddedToUser = $pathAdded
  RestartTerminalNeeded = $pathAdded
  CodexSkill = Join-Path $HOME '.codex\skills\ai-relay\SKILL.md'
  ClaudeSkill = Join-Path $HOME '.claude\skills\relay\SKILL.md'
  ClaudeCommands = Join-Path $HOME '.claude\commands'
} | Format-List
