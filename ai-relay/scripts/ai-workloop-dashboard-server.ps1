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
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
  } catch {
    Write-Host ("[{0}] HTTP response write skipped: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message)
  } finally {
    try {
      $Response.OutputStream.Close()
    } catch {
    }
  }
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

function New-CcRunnerStatusHtml {
  param(
    [string]$Project,
    [string]$Pair,
    [string]$BaseUrl
  )
  $pairDir = Get-AiRelayPairDir $Project $Pair
  $statusPath = Join-Path $pairDir 'cc-runner-status.json'
  $outputPath = Join-Path $pairDir 'cc-runner-output.md'
  $streamPath = Join-Path $pairDir 'cc-runner-stream.jsonl'
  $runnerStdoutPath = Join-Path $pairDir 'cc-runner-process.stdout.log'
  $runnerStderrPath = Join-Path $pairDir 'cc-runner-process.stderr.log'
  $reportPath = Join-Path $pairDir 'cc-report.md'
  $status = $null
  if (Test-Path -LiteralPath $statusPath) {
    try {
      $status = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
      $status = $null
    }
  }
  $statusText = if ($status -and $status.status) { [string]$status.status } else { 'unknown' }
  $message = if ($status -and $status.message) { [string]$status.message } else { '尚未写入状态文件。' }
  $updatedAt = if ($status -and $status.updatedAt) { [string]$status.updatedAt } else { '' }
  $processId = if ($status -and $status.processId) { [string]$status.processId } else { '' }
  if ($status -and $status.streamPath) {
    $streamPath = [string]$status.streamPath
  }
  if ($status -and $status.stdoutPath) {
    $runnerStdoutPath = [string]$status.stdoutPath
  }
  if ($status -and $status.stderrPath) {
    $runnerStderrPath = [string]$status.stderrPath
  }
  $processAlive = $false
  if ($processId -match '^\d+$') {
    $processAlive = [bool](Get-Process -Id ([int]$processId) -ErrorAction SilentlyContinue)
  }
  if ($statusText -in @('queued','started','running') -and $processId -and -not $processAlive) {
    $statusText = 'stale'
    $message = "$message`n`n检测到 runner 进程已经不存在，但状态文件仍是 running。请查看 stderr 日志，必要时重新执行。"
  }
  $output = ''
  if (Test-Path -LiteralPath $outputPath) {
    $output = Get-Content -LiteralPath $outputPath -Raw -Encoding utf8
    if ($output.Length -gt 12000) {
      $output = $output.Substring($output.Length - 12000)
    }
  }
  if ([string]::IsNullOrWhiteSpace($output)) {
    $output = "暂无 Claude stdout 输出。Claude CLI 的 --print 模式可能在任务完成后才一次性写入结果。`n`n如果状态仍是 running，请继续等待；也可以查看控制器窗口里的 cc-runner started pid。"
  }
  $stderr = ''
  if (Test-Path -LiteralPath $runnerStderrPath) {
    $stderr = Get-Content -LiteralPath $runnerStderrPath -Raw -Encoding utf8
    if ($stderr.Length -gt 6000) {
      $stderr = $stderr.Substring($stderr.Length - 6000)
    }
  }
  $reportInfo = if (Test-Path -LiteralPath $reportPath) {
    $item = Get-Item -LiteralPath $reportPath
    "cc-report.md 更新时间：$($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
  } else {
    'cc-report.md 尚不存在。'
  }
  $projectArg = [System.Uri]::EscapeDataString($Project)
  $pairArg = [System.Uri]::EscapeDataString($Pair)
  $refreshUrl = "$($BaseUrl.TrimEnd('/'))/status/cc-runner?projectRoot=$projectArg&pair=$pairArg"
  $stopUrl = "$($BaseUrl.TrimEnd('/'))/action/cc-runner-stop?projectRoot=$projectArg&pair=$pairArg"
  $refresh = if ($statusText -in @('queued','started','running','unknown')) {
    "<meta http-equiv='refresh' content='2;url=$(Encode-Html $refreshUrl)'>"
  } else {
    ''
  }
  $stopForm = if ($statusText -in @('queued','started','running') -and $processAlive) {
    @"
    <form method="post" action="$(Encode-Html $stopUrl)" onsubmit="return confirm('确认停止这个 CC runner 进程？');">
      <button type="submit">停止 CC 执行</button>
    </form>
"@
  } else {
    ''
  }
  @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  $refresh
  <title>CC 执行状态</title>
  <style>
    body { font-family: "Segoe UI", system-ui, sans-serif; margin: 24px; color: #1f2933; background: #f7f7f4; }
    main { max-width: 980px; margin: 0 auto; background: #fff; border: 1px solid #d8ddd8; border-radius: 8px; padding: 18px; }
    h1 { margin-top: 0; font-size: 22px; }
    .badge { display:inline-block; border:1px solid #d8ddd8; border-radius:999px; padding:4px 10px; background:#f5f6f2; }
    dl { display:grid; grid-template-columns:160px 1fr; gap:8px 12px; }
    dt { color:#65717d; }
    dd { margin:0; overflow-wrap:anywhere; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; background: #f5f6f2; border: 1px solid #e4e6df; border-radius: 6px; padding: 12px; }
    button { appearance:none; border:1px solid #b76a6a; border-radius:6px; background:#fff4f4; color:#8a2f2f; padding:8px 12px; font:inherit; cursor:pointer; }
    a { color: #176b5d; }
  </style>
</head>
<body>
  <main>
    <h1>CC 执行状态 <span class="badge">$(Encode-Html $statusText)</span></h1>
    <dl>
      <dt>Pair</dt><dd>$(Encode-Html $Pair)</dd>
      <dt>项目</dt><dd>$(Encode-Html $Project)</dd>
      <dt>状态说明</dt><dd>$(Encode-Html $message)</dd>
      <dt>更新时间</dt><dd>$(Encode-Html $updatedAt)</dd>
      <dt>进程 ID</dt><dd>$(Encode-Html $processId)</dd>
      <dt>报告状态</dt><dd>$(Encode-Html $reportInfo)</dd>
      <dt>输出文件</dt><dd>$(Encode-Html $outputPath)</dd>
      <dt>原始流</dt><dd>$(Encode-Html $streamPath)</dd>
      <dt>stderr 日志</dt><dd>$(Encode-Html $runnerStderrPath)</dd>
    </dl>
    $stopForm
    <h2>输出片段</h2>
    <pre>$(Encode-Html $output)</pre>
    <h2>stderr 片段</h2>
    <pre>$(Encode-Html $stderr)</pre>
    <p><a href="$(Encode-Html $refreshUrl)">手动刷新</a> · <a href="/">返回 Dashboard</a></p>
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

function Stop-ProcessTreeById {
  param([Parameter(Mandatory=$true)][int]$ProcessId)
  $children = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ParentProcessId -eq $ProcessId })
  foreach ($child in $children) {
    Stop-ProcessTreeById -ProcessId ([int]$child.ProcessId)
  }
  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if ($process) {
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
  }
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
  $path = [string]$Request.Url.AbsolutePath
  if ($path.Length -gt 1) {
    $path = $path.TrimEnd('/')
  }
  Write-Host ("[{0}] ACTION {1} {2}{3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Request.HttpMethod, $path, $Request.Url.Query)
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
      Write-Host ("[{0}] RUN workloop project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-workloop.ps1" $pair } finally { Pop-Location }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Workloop 执行结果' "<pre>$(Encode-Html $output)</pre>")
      return
    }

    if ($path -eq '/action/export') {
      Write-Host ("[{0}] RUN export project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-relay-export.ps1" -Pair $pair -Format both -Open } finally { Pop-Location }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml '审计报告生成结果' "<pre>$(Encode-Html $output)</pre>")
      return
    }

    if ($path -eq '/action/cc-runner') {
      Write-Host ("[{0}] RUN cc-runner project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      $pairDir = Get-AiRelayPairDir $project $pair
      if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair 不存在：$pairDir" }
      $statusPath = Join-Path $pairDir 'cc-runner-status.json'
      $runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
      $stdoutPath = Join-Path $pairDir "cc-runner-process-$runId.stdout.log"
      $stderrPath = Join-Path $pairDir "cc-runner-process-$runId.stderr.log"
      Write-AiRelayJson ([ordered]@{
        pairId = $pair
        projectRoot = $project
        status = 'queued'
        message = '已收到面板请求，正在启动 Claude Code runner。'
        exitCode = 0
        outputPath = Join-Path $pairDir 'cc-runner-output.md'
        streamPath = Join-Path $pairDir 'cc-runner-stream.jsonl'
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        updatedAt = (Get-Date).ToString('o')
        processId = ''
      }) $statusPath
      $powershell = Get-Command powershell -ErrorAction SilentlyContinue
      if (-not $powershell) { throw "powershell.exe not found." }
      $runnerPath = Join-Path $PSScriptRoot 'ai-workloop-cc-runner.ps1'
      $runnerOutputPath = Join-Path $pairDir 'cc-runner-output.md'
      $runnerStreamPath = Join-Path $pairDir 'cc-runner-stream.jsonl'
      $terminalCommand = @"
`$ErrorActionPreference = 'Continue'
try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
  `$OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {}
Set-Location -LiteralPath '$($project.Replace("'", "''"))'
Write-Host 'Agent Workloop CC runner'
Write-Host 'Pair: $($pair.Replace("'", "''"))'
Write-Host 'Project: $($project.Replace("'", "''"))'
Write-Host 'Live output: $($runnerOutputPath.Replace("'", "''"))'
Write-Host 'Raw stream: $($runnerStreamPath.Replace("'", "''"))'
Write-Host ''
if (Test-Path -LiteralPath '$($runnerOutputPath.Replace("'", "''"))') {
  Clear-Content -LiteralPath '$($runnerOutputPath.Replace("'", "''"))' -ErrorAction SilentlyContinue
} else {
  New-Item -ItemType File -Path '$($runnerOutputPath.Replace("'", "''"))' -Force | Out-Null
}
`$runner = Start-Process -FilePath '$($powershell.Source.Replace("'", "''"))' -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  '$($runnerPath.Replace("'", "''"))',
  '-Pair',
  '$($pair.Replace("'", "''"))'
) -WorkingDirectory '$($project.Replace("'", "''"))' -WindowStyle Hidden -RedirectStandardOutput '$($stdoutPath.Replace("'", "''"))' -RedirectStandardError '$($stderrPath.Replace("'", "''"))' -PassThru
Write-Host "Runner process: `$(`$runner.Id)"
Write-Host ''
Write-Host '--- Claude Code live output ---'
`$position = 0
while (-not `$runner.HasExited) {
  if (Test-Path -LiteralPath '$($runnerOutputPath.Replace("'", "''"))') {
    `$text = Get-Content -LiteralPath '$($runnerOutputPath.Replace("'", "''"))' -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    if (`$null -ne `$text -and `$text.Length -gt `$position) {
      Write-Host -NoNewline `$text.Substring(`$position)
      `$position = `$text.Length
    }
  }
  Start-Sleep -Milliseconds 700
  `$runner.Refresh()
}
if (Test-Path -LiteralPath '$($runnerOutputPath.Replace("'", "''"))') {
  `$text = Get-Content -LiteralPath '$($runnerOutputPath.Replace("'", "''"))' -Raw -Encoding utf8 -ErrorAction SilentlyContinue
  if (`$null -ne `$text -and `$text.Length -gt `$position) {
    Write-Host -NoNewline `$text.Substring(`$position)
  }
}
Write-Host ''
Write-Host "--- CC runner finished. ExitCode=`$(`$runner.ExitCode) ---"
Write-Host '窗口只用于观看输出；控制仍然通过面板或原 CC/Codex 会话完成。'
Read-Host '按 Enter 关闭窗口'
"@
      $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($terminalCommand))
      $process = Start-Process -FilePath $powershell.Source -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        $encodedCommand
      ) -WorkingDirectory $project -WindowStyle Normal -PassThru
      Write-Host ("[{0}] cc-runner started pid={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $process.Id)
      Write-AiRelayJson ([ordered]@{
        pairId = $pair
        projectRoot = $project
        status = 'started'
        message = '已启动可见 Claude Code runner 终端，等待 runner 写入运行状态。'
        exitCode = 0
        outputPath = Join-Path $pairDir 'cc-runner-output.md'
        streamPath = Join-Path $pairDir 'cc-runner-stream.jsonl'
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        updatedAt = (Get-Date).ToString('o')
        processId = $process.Id
      }) $statusPath
      $html = New-CcRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix
      Write-HttpText -Response $Response -Text $html
      return
    }

    if ($path -eq '/action/cc-runner-stop') {
      $pairDir = Get-AiRelayPairDir $project $pair
      $statusPath = Join-Path $pairDir 'cc-runner-status.json'
      if (-not (Test-Path -LiteralPath $statusPath)) { throw "状态文件不存在：$statusPath" }
      $status = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json
      $runnerProcessId = if ($status.processId) { [int]$status.processId } else { 0 }
      if ($runnerProcessId -gt 0) {
        Stop-ProcessTreeById -ProcessId $runnerProcessId
      }
      $status.status = 'stopped'
      $status.message = "用户从面板停止了 CC runner。"
      $status.updatedAt = (Get-Date).ToString('o')
      Write-AiRelayJson $status $statusPath
      Write-Host ("[{0}] STOP cc-runner project={1} pair={2} pid={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $runnerProcessId)
      Write-HttpText -Response $Response -Text (New-CcRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
      return
    }

    if ($path -eq '/action/review') {
      Write-Host ("[{0}] RUN review project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-relay-review.ps1" -Pair $pair -Format both -Open } finally { Pop-Location }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml '复盘报告生成结果' "<pre>$(Encode-Html $output)</pre>")
      return
    }

    Write-Host ("[{0}] UNKNOWN action path={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $path)
    Write-HttpText -Response $Response -Text (New-ResultHtml '未知操作' "<pre>$(Encode-Html $path)</pre>") -StatusCode 404
  } catch {
    Write-Host ("[{0}] ACTION failed path={1}: {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $path, $_.Exception.Message)
    Write-HttpText -Response $Response -Text (New-ResultHtml '操作失败' "<pre>$(Encode-Html $_.Exception.Message)</pre>") -StatusCode 500
  }
}

function Handle-Status {
  param(
    [System.Net.HttpListenerRequest]$Request,
    [System.Net.HttpListenerResponse]$Response
  )
  $query = Get-QueryMap $Request.Url
  $path = [string]$Request.Url.AbsolutePath
  if ($path.Length -gt 1) {
    $path = $path.TrimEnd('/')
  }
  try {
    $project = Assert-AllowedProject (Decode-Query $query['projectRoot'])
    $pair = Decode-Query $query['pair']
    Assert-AiRelayPairName $pair
    if ($path -eq '/status/cc-runner') {
      Write-HttpText -Response $Response -Text (New-CcRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
      return
    }
    Write-HttpText -Response $Response -Text (New-ResultHtml '未知状态页' "<pre>$(Encode-Html $path)</pre>") -StatusCode 404
  } catch {
    Write-HttpText -Response $Response -Text (New-ResultHtml '状态读取失败' "<pre>$(Encode-Html $_.Exception.Message)</pre>") -StatusCode 500
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
    } elseif ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath.StartsWith('/status/')) {
      Handle-Status -Request $request -Response $response
    } elseif ($request.HttpMethod -eq 'POST' -and $request.Url.AbsolutePath.StartsWith('/action/')) {
      Handle-Action -Request $request -Response $response
    } else {
      Write-Host ("[{0}] NOT_FOUND {1} {2}{3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $request.HttpMethod, $request.Url.AbsolutePath, $request.Url.Query)
      Write-HttpText -Response $response -Text (New-ResultHtml 'Not Found' '<pre>Not Found</pre>') -StatusCode 404
    }
  }
} finally {
  if ($listener.IsListening) {
    $listener.Stop()
  }
  $listener.Close()
}
