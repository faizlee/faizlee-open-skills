param(
  [string[]]$ProjectRoot,
  [int]$Port = 17877,
  [switch]$Open
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

$workloopHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$dashboardConfigDir = Join-Path $workloopHome '.ai-tools\workloop-dashboard'
$projectConfigPath = Join-Path $dashboardConfigDir 'projects.json'

function Write-HttpText {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [string]$Text,
    [string]$ContentType = 'text/html; charset=utf-8',
    [int]$StatusCode = 200
  )
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Response.StatusCode = $StatusCode
  $Response.ContentType = $ContentType
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Response.OutputStream.Close()
}

function Encode-Html {
  param([string]$Text)
  [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Decode-Query {
  param([string]$Text)
  [System.Net.WebUtility]::UrlDecode([string]$Text)
}

function Read-RegisteredProjects {
  if (Test-Path -LiteralPath $projectConfigPath) {
    try {
      $data = Get-Content -LiteralPath $projectConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
      if ($data.projects) {
        return @($data.projects | ForEach-Object { [string]$_ })
      }
    } catch {
      Write-Warning "无法读取项目注册表：$projectConfigPath"
    }
  }
  return @()
}

function Expand-ProjectArgs {
  param([string[]]$Roots)
  $items = @()
  foreach ($root in $Roots) {
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    $items += ([string]$root -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") })
  }
  return @($items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-AllowedProjects {
  $inputs = @()
  if ($ProjectRoot -and $ProjectRoot.Count -gt 0) {
    $inputs = Expand-ProjectArgs $ProjectRoot
  } else {
    $inputs = @(Read-RegisteredProjects)
    if (-not $inputs) {
      $inputs = @((Get-Location).ProviderPath)
    }
  }

  $resolved = @()
  foreach ($item in $inputs) {
    $path = Resolve-Path -LiteralPath $item -ErrorAction SilentlyContinue
    if ($path) { $resolved += $path.ProviderPath }
  }
  return @($resolved | Sort-Object -Unique)
}

function Assert-AllowedProject {
  param([string]$Project)
  $resolved = Resolve-Path -LiteralPath $Project -ErrorAction Stop
  $target = $resolved.ProviderPath.TrimEnd('\').ToLowerInvariant()
  $allowed = @(Get-AllowedProjects | ForEach-Object { $_.TrimEnd('\').ToLowerInvariant() })
  if ($allowed -notcontains $target) {
    throw "项目未注册或未传入本控制器：$Project"
  }
  return $resolved.ProviderPath
}

function Get-QueryMap {
  param([System.Uri]$Uri)
  $map = @{}
  $query = $Uri.Query
  if ($query.StartsWith('?')) { $query = $query.Substring(1) }
  foreach ($part in ($query -split '&')) {
    if ([string]::IsNullOrWhiteSpace($part)) { continue }
    $kv = $part -split '=', 2
    $key = Decode-Query $kv[0]
    $value = if ($kv.Count -gt 1) { Decode-Query $kv[1] } else { '' }
    $map[$key] = $value
  }
  return $map
}

function New-ResultHtml {
  param([string]$Title, [string]$Body)
  @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$(Encode-Html $Title)</title>
  <style>
    body { font-family: "Segoe UI", system-ui, sans-serif; margin: 24px; color: #1f2933; background: #f7f7f4; }
    main { max-width: 980px; margin: 0 auto; background: #fff; border: 1px solid #d8ddd8; border-radius: 8px; padding: 18px; }
    h1 { margin-top: 0; font-size: 22px; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; background: #f5f6f2; border: 1px solid #e4e6df; border-radius: 6px; padding: 12px; }
    a { color: #176b5d; }
  </style>
</head>
<body>
  <main>
    <h1>$(Encode-Html $Title)</h1>
    $Body
    <p><a href="/">返回 Dashboard</a></p>
  </main>
</body>
</html>
"@
}

function Invoke-Captured {
  param([scriptblock]$Script)
  $output = & $Script 2>&1 | Out-String
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    $output += "`nLASTEXITCODE=$LASTEXITCODE"
  }
  return $output
}

function Serve-Dashboard {
  param([System.Net.HttpListenerResponse]$Response, [string]$BaseUrl)
  $outDir = Join-Path $dashboardConfigDir 'server'
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $args = @('-OutDir', $outDir, '-ControlBaseUrl', $BaseUrl)
  $allowed = @(Get-AllowedProjects)
  if ($allowed) {
    $args += '-ProjectRoot'
    $args += ($allowed -join ',')
  }
  $powershell = Get-Command powershell -ErrorAction SilentlyContinue
  if ($powershell) {
    & $powershell.Source -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\ai-workloop-dashboard.ps1" @args | Out-Null
  } else {
    & "$PSScriptRoot\ai-workloop-dashboard.ps1" @args | Out-Null
  }
  $htmlPath = Join-Path $outDir 'index.html'
  $html = Get-Content -LiteralPath $htmlPath -Raw -Encoding utf8
  Write-HttpText -Response $Response -Text $html
}

function Handle-Action {
  param(
    [System.Net.HttpListenerRequest]$Request,
    [System.Net.HttpListenerResponse]$Response
  )
  $query = Get-QueryMap $Request.Url
  $path = $Request.Url.AbsolutePath
  try {
    if ($path -eq '/action/open') {
      $target = Decode-Query $query['path']
      if (-not (Test-Path -LiteralPath $target)) { throw "路径不存在：$target" }
      Invoke-Item -LiteralPath $target
      Write-HttpText -Response $Response -Text (New-ResultHtml '已打开' "<pre>$(Encode-Html $target)</pre>")
      return
    }

    $project = Assert-AllowedProject (Decode-Query $query['projectRoot'])
    $pair = Decode-Query $query['pair']
    Assert-AiRelayPairName $pair

    if ($path -eq '/action/workloop') {
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-workloop.ps1" $pair } finally { Pop-Location }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Workloop 执行结果' "<pre>$(Encode-Html $output)</pre>")
      return
    }

    if ($path -eq '/action/export') {
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-relay-export.ps1" -Pair $pair -Format both -Open } finally { Pop-Location }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml '审计报告生成结果' "<pre>$(Encode-Html $output)</pre>")
      return
    }

    if ($path -eq '/action/cc-runner') {
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-workloop-cc-runner.ps1" -Pair $pair } finally { Pop-Location }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Claude Code Runner 执行结果' "<pre>$(Encode-Html $output)</pre>")
      return
    }

    if ($path -eq '/action/review') {
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-relay-review.ps1" -Pair $pair -Format both -Open } finally { Pop-Location }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml '复盘报告生成结果' "<pre>$(Encode-Html $output)</pre>")
      return
    }

    Write-HttpText -Response $Response -Text (New-ResultHtml '未知操作' "<pre>$(Encode-Html $path)</pre>") -StatusCode 404
  } catch {
    Write-HttpText -Response $Response -Text (New-ResultHtml '操作失败' "<pre>$(Encode-Html $_.Exception.Message)</pre>") -StatusCode 500
  }
}

$prefix = "http://127.0.0.1:$Port/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)

try {
  $listener.Start()
} catch {
  throw "无法启动本地控制器 $prefix。请换一个 -Port，或检查系统是否允许 HttpListener。原始错误：$($_.Exception.Message)"
}

Write-Host "Agent Workloop 控制面板已启动：$prefix"
Write-Host "这是前台 localhost 控制器；关闭此 PowerShell 窗口即停止。"
Write-Host "可能消耗 Codex 额度的操作会在网页按钮上二次确认。"

if ($Open) {
  Start-Process $prefix
}

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    if ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath -eq '/') {
      Serve-Dashboard -Response $response -BaseUrl $prefix
    } elseif ($request.HttpMethod -eq 'POST' -and $request.Url.AbsolutePath.StartsWith('/action/')) {
      Handle-Action -Request $request -Response $response
    } else {
      Write-HttpText -Response $response -Text (New-ResultHtml 'Not Found' '<pre>Not Found</pre>') -StatusCode 404
    }
  }
} finally {
  if ($listener.IsListening) {
    $listener.Stop()
  }
  $listener.Close()
}
