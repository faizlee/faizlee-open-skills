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

function Get-RequestFormMap {
  param([System.Net.HttpListenerRequest]$Request)
  $map = @{}
  if (-not $Request.HasEntityBody) { return $map }
  $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
  try {
    $body = $reader.ReadToEnd()
  } finally {
    $reader.Close()
  }
  foreach ($part in ($body -split '&')) {
    if ([string]::IsNullOrWhiteSpace($part)) { continue }
    $kv = $part -split '=', 2
    $key = Decode-Query (($kv[0] -replace '\+', ' '))
    $value = if ($kv.Count -gt 1) { Decode-Query (($kv[1] -replace '\+', ' ')) } else { '' }
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

function New-WorkloopCodexSessionId {
  param(
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$Pair
  )
  $codex = Get-Command codex -ErrorAction SilentlyContinue
  if (-not $codex) { throw "codex CLI not found in PATH." }
  $pairDir = Get-AiRelayPairDir $Project $Pair
  New-Item -ItemType Directory -Force -Path $pairDir | Out-Null
  $initOut = Join-Path $pairDir 'codex-session-init.md'
  $prompt = @"
Initialize Agent Workloop pair "$Pair" for this project.

Rules:
- You are the Codex commander thread for this pair.
- Do not modify files.
- Do not use subagents.
- Do not start codex-with-cc.
- Do not use --last.
- Reply with one short sentence: Agent Workloop Codex session initialized.
"@
  $output = & $codex.Source exec --json --sandbox read-only -C $Project -o $initOut $prompt 2>&1 | Out-String
  $exitCode = $LASTEXITCODE
  Set-Content -LiteralPath (Join-Path $pairDir 'codex-session-init.log') -Value $output -Encoding utf8
  if ($exitCode -ne 0) {
    throw "创建 Codex session 失败。ExitCode=$exitCode`n$output"
  }
  $matches = [regex]::Matches($output, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
  if ($matches.Count -lt 1) {
    throw "创建 Codex session 成功但无法从输出解析 session id。日志：$(Join-Path $pairDir 'codex-session-init.log')"
  }
  return $matches[0].Value
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

    if ($path -eq '/action/create-pair') {
      $form = Get-RequestFormMap $Request
      $project = Assert-AllowedProject ([string]$form['projectRoot'])
      $pair = [string]$form['pair']
      $task = [string]$form['task']
      $codexSessionId = ([string]$form['codexSessionId']).Trim()
      Assert-AiRelayPairName $pair
      Write-Host ("[{0}] CREATE pair project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-relay-bind-cc.ps1" -Pair $pair -Task $task } finally { Pop-Location }
      }
      $bindOutput = ''
      if ([string]::IsNullOrWhiteSpace($codexSessionId)) {
        $codexSessionId = New-WorkloopCodexSessionId -Project $project -Pair $pair
      }
      if ($codexSessionId -notmatch '^[0-9a-fA-F-]{20,}$') {
        throw "Codex Session ID 格式看起来不正确：$codexSessionId"
      }
      $bindOutput = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-relay-bind-codex.ps1" -Pair $pair -CodexSessionId $codexSessionId -Force } finally { Pop-Location }
      }
      $bindPath = Join-Path (Get-AiRelayPairDir $project $pair) 'bind-request.md'
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Pair 已创建并绑定' "<p>已创建 Pair，并绑定 Codex session。</p><p>Codex session id: <code>$(Encode-Html $codexSessionId)</code></p><pre>$(Encode-Html ($output + "`n" + $bindOutput))</pre><p>Bind request: <code>$(Encode-Html $bindPath)</code></p>")
      return
    }

    if ($path -eq '/action/discover-projects') {
      $form = Get-RequestFormMap $Request
      $scanRoot = [string]$form['scanRoot']
      $depth = 2
      if ([string]$form['depth'] -match '^\d+$') {
        $depth = [int]$form['depth']
      }
      if ($depth -lt 1) { $depth = 1 }
      if ($depth -gt 5) { $depth = 5 }
      Write-Host ("[{0}] DISCOVER projects root={1} depth={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $scanRoot, $depth)
      $output = Invoke-Captured {
        & "$PSScriptRoot\ai-workloop-project.ps1" -Mode discover-add -ScanRoot $scanRoot -Depth $depth
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml '项目扫描完成' "<p>已扫描并添加候选项目。刷新面板后可在项目列表和创建 Pair 下拉框中看到。</p><pre>$(Encode-Html $output)</pre>")
      return
    }

    if ($path -eq '/action/rebind-codex') {
      $form = Get-RequestFormMap $Request
      $project = Assert-AllowedProject ([string]$form['projectRoot'])
      $pair = [string]$form['pair']
      $codexSessionId = ([string]$form['codexSessionId']).Trim()
      Assert-AiRelayPairName $pair
      if ([string]::IsNullOrWhiteSpace($codexSessionId)) {
        $codexSessionId = New-WorkloopCodexSessionId -Project $project -Pair $pair
      }
      if ($codexSessionId -notmatch '^[0-9a-fA-F-]{20,}$') {
        throw "Codex Session ID 格式看起来不正确：$codexSessionId"
      }
      Write-Host ("[{0}] REBIND codex project={1} pair={2} session={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $codexSessionId)
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-relay-bind-codex.ps1" -Pair $pair -CodexSessionId $codexSessionId -Force } finally { Pop-Location }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Codex 绑定已更新' "<p>Pair 已绑定/重绑到 Codex session。</p><p>Codex session id: <code>$(Encode-Html $codexSessionId)</code></p><pre>$(Encode-Html $output)</pre>")
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
Write-Host 'Mode: Claude Code native terminal'
Write-Host ''
`$pairDir = '$($pairDir.Replace("'", "''"))'
`$pairJsonPath = Join-Path `$pairDir 'pair.json'
`$sourcePath = Join-Path `$pairDir 'cc-inbox.md'
`$statusPath = Join-Path `$pairDir 'cc-runner-status.json'
`$pairJson = Get-Content -LiteralPath `$pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
`$ccSessionId = [string]`$pairJson.ccSessionId
`$sourceText = Get-Content -LiteralPath `$sourcePath -Raw -Encoding utf8
if ([string]::IsNullOrWhiteSpace(`$ccSessionId)) {
  Write-Host 'pair.json 缺少 ccSessionId，请先 rebind。' -ForegroundColor Red
  Read-Host '按 Enter 关闭窗口'
  exit 1
}
if ([string]::IsNullOrWhiteSpace(`$sourceText)) {
  Write-Host 'cc-inbox.md 为空，没有可执行任务。' -ForegroundColor Yellow
  Read-Host '按 Enter 关闭窗口'
  exit 1
}
`$status = [ordered]@{
  pairId = '$($pair.Replace("'", "''"))'
  projectRoot = '$($project.Replace("'", "''"))'
  status = 'running'
  message = '已打开 Claude Code 原生终端执行任务。'
  exitCode = 0
  outputPath = '$($runnerOutputPath.Replace("'", "''"))'
  streamPath = '$($runnerStreamPath.Replace("'", "''"))'
  stdoutPath = '$($stdoutPath.Replace("'", "''"))'
  stderrPath = '$($stderrPath.Replace("'", "''"))'
  updatedAt = (Get-Date).ToString('o')
  processId = `$PID
}
`$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath `$statusPath -Encoding utf8
`$prompt = @(
  'You are the Claude Code execution agent for Agent Workloop pair "$($pair.Replace("'", "''"))".',
  '',
  'Project root:',
  '$($project.Replace("'", "''"))',
  '',
  'Read the task below, execute only what is requested, then write a compressed report to:',
  '.ai-relay/pairs/$($pair.Replace("'", "''"))/cc-report.md',
  '',
  'Report requirements:',
  '- Use the existing CC Report format.',
  '- Include changed files and verification commands.',
  '- Do not paste long logs or full diffs.',
  '- If execution is unsafe or unclear, write that in the report instead of guessing.',
  '- Do not auto-push unless the task explicitly asks.',
  '',
  'Task:',
  `$sourceText
) -join [Environment]::NewLine
`$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not `$claude) {
  Write-Host 'claude CLI not found in PATH.' -ForegroundColor Red
  Read-Host '按 Enter 关闭窗口'
  exit 1
}
Write-Host "Resuming Claude Code session: `$ccSessionId"
Write-Host '下面是 Claude Code 原生终端输出。'
Write-Host ''
& `$claude.Source --resume `$ccSessionId --permission-mode default `$prompt
`$exitCode = `$LASTEXITCODE
try {
  `$status.status = if (`$exitCode -eq 0) { 'completed' } else { 'failed' }
  `$status.exitCode = `$exitCode
  `$status.message = "Claude Code 原生终端执行结束。ExitCode=`$exitCode"
  `$status.updatedAt = (Get-Date).ToString('o')
  `$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath `$statusPath -Encoding utf8
} catch {
  Write-Host "写入状态失败：`$(`$_.Exception.Message)" -ForegroundColor Yellow
}
if (`$exitCode -ne 0) {
  Write-Host ''
  Write-Host "Claude Code exited with code `$exitCode" -ForegroundColor Red
} else {
  Write-Host ''
  Write-Host 'Claude Code 执行结束。' -ForegroundColor Green
  }
Write-Host '窗口用于观看 Claude Code 原生输出；控制仍然可以通过面板或原 CC/Codex 会话完成。'
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
        message = '已启动 Claude Code 原生终端，等待终端写入运行状态。'
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

    if ($path -eq '/action/archive-pair') {
      $pairDir = Get-AiRelayPairDir $project $pair
      if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair 不存在：$pairDir" }
      $statusPath = Join-Path $pairDir 'cc-runner-status.json'
      if (Test-Path -LiteralPath $statusPath) {
        try {
          $status = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json
          if ($status.status -in @('queued','started','running') -and $status.processId) {
            $running = Get-Process -Id ([int]$status.processId) -ErrorAction SilentlyContinue
            if ($running) { throw "Pair 正在运行，不能归档。请先停止 CC 执行。" }
          }
        } catch {
          if ($_.Exception.Message -like '*正在运行*') { throw }
        }
      }
      $archiveRoot = Join-Path (Get-AiRelayRoot $project) 'archived-pairs'
      New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
      $destination = Join-Path $archiveRoot $pair
      if (Test-Path -LiteralPath $destination) {
        $destination = Join-Path $archiveRoot ("{0}-{1}" -f $pair, (Get-Date -Format 'yyyyMMdd-HHmmss'))
      }
      Move-Item -LiteralPath $pairDir -Destination $destination
      $currentPath = Join-Path (Get-AiRelayRoot $project) 'current-pair.json'
      if (Test-Path -LiteralPath $currentPath) {
        try {
          $current = Get-Content -LiteralPath $currentPath -Raw -Encoding utf8 | ConvertFrom-Json
          if ([string]$current.pairId -eq $pair) {
            Remove-Item -LiteralPath $currentPath -Force
          }
        } catch {
        }
      }
      Write-Host ("[{0}] ARCHIVE pair project={1} pair={2} destination={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $destination)
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Pair 已归档' "<p>Pair 已移动到 archived-pairs，不会出现在普通面板列表中。</p><pre>$(Encode-Html $destination)</pre>")
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
