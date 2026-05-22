param(
  [ValidateSet('add','remove','list','clear')][string]$Mode = 'list',
  [string[]]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

$configDir = Join-Path $HOME '.ai-tools\workloop-dashboard'
$configPath = Join-Path $configDir 'projects.json'

function Read-WorkloopProjects {
  if (Test-Path -LiteralPath $configPath) {
    try {
      $data = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
      if ($data.projects) {
        return @($data.projects | ForEach-Object { [string]$_ })
      }
    } catch {
      Write-Warning "无法读取项目注册表，将使用空列表：$configPath"
    }
  }
  return @()
}

function Write-WorkloopProjects {
  param([string[]]$Projects)
  New-Item -ItemType Directory -Force -Path $configDir | Out-Null
  [ordered]@{
    updatedAt = (Get-Date).ToString('o')
    projects = @($Projects | Sort-Object -Unique)
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding utf8
}

function Expand-WorkloopProjectArgs {
  param([string[]]$Roots)
  $items = @()
  foreach ($root in $Roots) {
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    $items += ([string]$root -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") })
  }
  return @($items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$current = @(Read-WorkloopProjects)

switch ($Mode) {
  'add' {
    $items = Expand-WorkloopProjectArgs $ProjectRoot
    if (-not $items) {
      $items = @((Get-Location).ProviderPath)
    }
    $resolved = @()
    foreach ($item in $items) {
      $path = Resolve-Path -LiteralPath $item -ErrorAction SilentlyContinue
      if ($path) {
        $resolved += $path.ProviderPath
      } else {
        Write-Warning "项目目录不存在，已跳过：$item"
      }
    }
    Write-WorkloopProjects -Projects @($current + $resolved)
    Write-Output "AI_WORKLOOP_PROJECTS_CONFIG=$configPath"
    Write-Output "AI_WORKLOOP_PROJECTS_COUNT=$(@(Read-WorkloopProjects).Count)"
  }
  'remove' {
    $items = Expand-WorkloopProjectArgs $ProjectRoot
    if (-not $items) {
      throw "remove 需要 -ProjectRoot。"
    }
    $removeSet = @{}
    foreach ($item in $items) {
      $path = Resolve-Path -LiteralPath $item -ErrorAction SilentlyContinue
      if ($path) {
        $removeSet[$path.ProviderPath.ToLowerInvariant()] = $true
      } else {
        $removeSet[$item.ToLowerInvariant()] = $true
      }
    }
    $next = @($current | Where-Object { -not $removeSet.ContainsKey(([string]$_).ToLowerInvariant()) })
    Write-WorkloopProjects -Projects $next
    Write-Output "AI_WORKLOOP_PROJECTS_CONFIG=$configPath"
    Write-Output "AI_WORKLOOP_PROJECTS_COUNT=$(@(Read-WorkloopProjects).Count)"
  }
  'clear' {
    Write-WorkloopProjects -Projects @()
    Write-Output "AI_WORKLOOP_PROJECTS_CONFIG=$configPath"
    Write-Output "AI_WORKLOOP_PROJECTS_COUNT=0"
  }
  'list' {
    Write-Output "AI_WORKLOOP_PROJECTS_CONFIG=$configPath"
    $projects = @(Read-WorkloopProjects)
    Write-Output "AI_WORKLOOP_PROJECTS_COUNT=$($projects.Count)"
    $projects | ForEach-Object { Write-Output $_ }
  }
}
