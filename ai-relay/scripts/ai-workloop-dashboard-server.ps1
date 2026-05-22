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
  $runUrl = "$($BaseUrl.TrimEnd('/'))/action/cc-runner?projectRoot=$projectArg&pair=$pairArg"
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
  $runForm = if (-not ($statusText -in @('queued','started','running') -and $processAlive)) {
    @"
    <form method="post" action="$(Encode-Html $runUrl)" onsubmit="return confirm('确认重新启动这个 pair 的 CC 执行？');">
      <button class="secondary" type="submit">重新执行</button>
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
    button.secondary { border-color:#8a927f; background:#f5f6f2; color:#25301f; }
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
    $runForm
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

function Get-ActiveCcRunnerStatus {
  param([Parameter(Mandatory=$true)][string]$StatusPath)
  if (-not (Test-Path -LiteralPath $StatusPath)) {
    return $null
  }
  try {
    $status = Get-Content -LiteralPath $StatusPath -Raw -Encoding utf8 | ConvertFrom-Json
  } catch {
    return $null
  }
  $state = if ($status.status) { [string]$status.status } else { '' }
  if ($state -notin @('queued','started','running')) {
    return $null
  }
  $pidText = if ($status.processId) { [string]$status.processId } else { '' }
  if ($pidText -match '^\d+$') {
    $process = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
    if ($process) {
      return $status
    }
  }
  $status.status = 'stale'
  $status.message = "检测到上一次 CC runner 状态是 $state，但进程已不存在。已标记为 stale，可重新执行。"
  $status.updatedAt = (Get-Date).ToString('o')
  Write-AiRelayJson $status $StatusPath
  return $null
}

function Test-WorkloopServerUnreadFile {
  param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$ReadPath
  )
  $source = Read-AiRelayTextFile $SourcePath
  if ([string]::IsNullOrWhiteSpace($source)) { return $false }
  if ((Test-Path -LiteralPath $SourcePath) -and (Test-Path -LiteralPath $ReadPath)) {
    if ((Get-Item -LiteralPath $ReadPath).LastWriteTime -ge (Get-Item -LiteralPath $SourcePath).LastWriteTime) {
      return $false
    }
  }
  $read = Read-AiRelayTextFile $ReadPath
  $normalizedSource = ($source -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  $normalizedRead = ($read -replace "^\uFEFF", '' -replace "`r`n", "`n").Trim()
  return ($normalizedSource -ne $normalizedRead)
}

function Get-WorkloopRoute {
  param([Parameter(Mandatory=$true)][string]$PairDir)
  $inboxPath = Join-Path $PairDir 'cc-inbox.md'
  $inboxReadPath = Join-Path $PairDir 'cc-inbox.read.md'
  $reportPath = Join-Path $PairDir 'cc-report.md'
  $replyPath = Join-Path $PairDir 'codex-reply.md'
  $replyReadPath = Join-Path $PairDir 'codex-reply.read.md'

  $report = Read-AiRelayTextFile $reportPath
  $reportReady = $false
  if (-not [string]::IsNullOrWhiteSpace($report) -and (Test-Path -LiteralPath $reportPath)) {
    $replyMissing = -not (Test-Path -LiteralPath $replyPath)
    $reportReady = $replyMissing -or ((Get-Item -LiteralPath $reportPath).LastWriteTime -gt (Get-Item -LiteralPath $replyPath).LastWriteTime)
  }
  if ($reportReady) {
    return [pscustomobject]@{
      Action = 'send-report'
      Source = ''
      SourcePath = $reportPath
      ReadPath = ''
      Message = 'cc-report.md 比 codex-reply.md 新，下一步是送 Codex 裁决，不应重复执行 CC。'
    }
  }

  $replyUnread = Test-WorkloopServerUnreadFile -SourcePath $replyPath -ReadPath $replyReadPath
  if ($replyUnread -and (Test-Path -LiteralPath $replyPath)) {
    if ((-not (Test-Path -LiteralPath $reportPath)) -or ((Get-Item -LiteralPath $replyPath).LastWriteTime -ge (Get-Item -LiteralPath $reportPath).LastWriteTime)) {
      return [pscustomobject]@{
        Action = 'run-cc'
        Source = 'codex-reply'
        SourcePath = $replyPath
        ReadPath = $replyReadPath
        Message = '发现未读 Codex 裁决，下一步让 CC 执行 codex-reply.md。'
      }
    }
  }

  $inboxUnread = Test-WorkloopServerUnreadFile -SourcePath $inboxPath -ReadPath $inboxReadPath
  if ($inboxUnread) {
    return [pscustomobject]@{
      Action = 'run-cc'
      Source = 'cc-inbox'
      SourcePath = $inboxPath
      ReadPath = $inboxReadPath
      Message = '发现未读 Codex 任务，下一步让 CC 执行 cc-inbox.md。'
    }
  }

  return [pscustomobject]@{
    Action = 'idle'
    Source = ''
    SourcePath = ''
    ReadPath = ''
    Message = '当前没有待送审报告、未读 Codex 裁决或未读任务。'
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
  $oldErrorActionPreference = $ErrorActionPreference
  $oldNativePreference = $null
  $hadNativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
  if ($hadNativePreference) { $oldNativePreference = $PSNativeCommandUseErrorActionPreference }
  try {
    $ErrorActionPreference = 'Continue'
    if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $false }
    $output = & $codex.Source exec --json --ignore-user-config --sandbox read-only -C $Project -o $initOut $prompt 2>&1 | Out-String
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
    if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $oldNativePreference }
  }
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

function New-WorkloopClaudeSessionId {
  param(
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$Pair
  )
  $claude = Get-Command claude -ErrorAction SilentlyContinue
  if (-not $claude) { throw "claude CLI not found in PATH." }
  $prompt = @"
Initialize Agent Workloop pair "$Pair" for this project.

Rules:
- You are the Claude Code execution thread for this pair.
- Do not modify files.
- Do not run tools unless needed.
- Reply with one short sentence: Agent Workloop Claude Code session initialized.
"@
  $output = & $claude.Source --print --output-format json --permission-mode plan $prompt 2>&1 | Out-String
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "创建 Claude Code session 失败。ExitCode=$exitCode`n$output"
  }
  try {
    $json = $output | ConvertFrom-Json
    if ($json.session_id) {
      return [pscustomobject]@{
        SessionId = [string]$json.session_id
        Output = $output
      }
    }
  } catch {
  }
  $matches = [regex]::Matches($output, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
  if ($matches.Count -lt 1) {
    throw "创建 Claude Code session 成功但无法从输出解析 session id。原始输出：$output"
  }
  return [pscustomobject]@{
    SessionId = $matches[0].Value
    Output = $output
  }
}

function Set-WorkloopCcSessionId {
  param(
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$Pair,
    [Parameter(Mandatory=$true)][string]$CcSessionId
  )
  $pairDir = Get-AiRelayPairDir $Project $Pair
  if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair 不存在：$pairDir" }
  $pairJsonPath = Join-Path $pairDir 'pair.json'
  $bindPath = Join-Path $pairDir 'bind-request.md'
  $bindValues = @{}
  if (Test-Path -LiteralPath $bindPath) {
    $bindTextForValues = Get-Content -LiteralPath $bindPath -Raw -Encoding utf8
    foreach ($name in @('task','ccInboxPath','ccReportPath','codexReplyPath')) {
      $m = [regex]::Match($bindTextForValues, "(?m)^$([regex]::Escape($name)):[ \t]*(.*)$")
      if ($m.Success) { $bindValues[$name] = $m.Groups[1].Value.Trim() }
    }
  }
  if (Test-Path -LiteralPath $pairJsonPath) {
    $pairJson = Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
    $pairJson.ccSessionId = $CcSessionId
    if (-not $pairJson.ccSessionName) {
      $pairJson | Add-Member -NotePropertyName ccSessionName -NotePropertyValue $CcSessionId -Force
    } else {
      $pairJson.ccSessionName = $CcSessionId
    }
    $pairJson.boundAt = (Get-Date).ToString('o')
    Write-AiRelayJson $pairJson $pairJsonPath
  } else {
    Write-AiRelayJson ([ordered]@{
      pairId = $Pair
      projectRoot = $Project
      task = if ($bindValues.ContainsKey('task')) { $bindValues['task'] } else { '' }
      codexSessionId = ''
      ccSessionId = $CcSessionId
      ccSessionName = $CcSessionId
      ccInboxPath = if ($bindValues.ContainsKey('ccInboxPath')) { $bindValues['ccInboxPath'] } else { Join-Path $pairDir 'cc-inbox.md' }
      ccReportPath = if ($bindValues.ContainsKey('ccReportPath')) { $bindValues['ccReportPath'] } else { Join-Path $pairDir 'cc-report.md' }
      codexReplyPath = if ($bindValues.ContainsKey('codexReplyPath')) { $bindValues['codexReplyPath'] } else { Join-Path $pairDir 'codex-reply.md' }
      role = 'commander'
      boundAt = (Get-Date).ToString('o')
    }) $pairJsonPath
  }
  if (Test-Path -LiteralPath $bindPath) {
    $bindText = Get-Content -LiteralPath $bindPath -Raw -Encoding utf8
    if ($bindText -match '(?m)^ccSessionId:') {
      $bindText = [regex]::Replace($bindText, '(?m)^ccSessionId:.*$', "ccSessionId: $CcSessionId")
    } else {
      $bindText = $bindText -replace '(?m)^ccSessionName:', "ccSessionId: $CcSessionId`nccSessionName:"
    }
    if ($bindText -match '(?m)^ccSessionName:') {
      $bindText = [regex]::Replace($bindText, '(?m)^ccSessionName:.*$', "ccSessionName: $CcSessionId")
    }
    Set-Content -LiteralPath $bindPath -Value $bindText -Encoding utf8
  }
  Add-AiRelayLog -PairDir $pairDir -Event 'bind-cc-session' -Detail "Bound Claude Code session id $CcSessionId."
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
      $item = Get-Item -LiteralPath $target
      if ($item.PSIsContainer) {
        Start-Process -FilePath explorer.exe -ArgumentList @($item.FullName) | Out-Null
      } else {
        try {
          Start-Process -FilePath $item.FullName -ErrorAction Stop | Out-Null
        } catch {
          $notepad = Get-Command notepad.exe -ErrorAction SilentlyContinue
          if (-not $notepad) { throw }
          Start-Process -FilePath $notepad.Source -ArgumentList @($item.FullName) | Out-Null
        }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml '已打开' "<pre>$(Encode-Html $target)</pre>")
      return
    }

    if ($path -eq '/action/create-pair') {
      $form = Get-RequestFormMap $Request
      $project = Assert-AllowedProject ([string]$form['projectRoot'])
      $pair = [string]$form['pair']
      $task = [string]$form['task']
      $codexSessionId = ([string]$form['codexSessionId']).Trim()
      $ccSessionId = ([string]$form['ccSessionId']).Trim()
      Assert-AiRelayPairName $pair
      Write-Host ("[{0}] CREATE pair project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      $ccInitOutput = ''
      if ([string]::IsNullOrWhiteSpace($ccSessionId)) {
        $ccSessionId = ''
        $ccInitOutput = 'Claude Code session id was not pre-created. The dashboard runner will open a new native Claude Code terminal when executing this pair.'
      }
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-relay-bind-cc.ps1" -Pair $pair -Task $task -CcSessionId $ccSessionId } finally { Pop-Location }
      }
      if ($ccInitOutput) {
        Set-Content -LiteralPath (Join-Path (Get-AiRelayPairDir $project $pair) 'cc-session-init.log') -Value $ccInitOutput -Encoding utf8
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
      $ccBindLabel = if ([string]::IsNullOrWhiteSpace($ccSessionId)) { '未预绑定；执行时打开新的 Claude Code 原生终端' } else { $ccSessionId }
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Pair 已创建并绑定' "<p>已创建 Pair，并绑定 Codex。Claude Code 可在执行时启动原生终端。</p><p>Codex session id: <code>$(Encode-Html $codexSessionId)</code></p><p>Claude Code session: <code>$(Encode-Html $ccBindLabel)</code></p><pre>$(Encode-Html ($output + "`n" + $bindOutput))</pre><p>Bind request: <code>$(Encode-Html $bindPath)</code></p>")
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

    if ($path -eq '/action/plan-task') {
      $form = Get-RequestFormMap $Request
      $projectText = if ($form.ContainsKey('projectRoot') -and -not [string]::IsNullOrWhiteSpace([string]$form['projectRoot'])) { [string]$form['projectRoot'] } else { Decode-Query $query['projectRoot'] }
      $pair = if ($form.ContainsKey('pair') -and -not [string]::IsNullOrWhiteSpace([string]$form['pair'])) { [string]$form['pair'] } else { Decode-Query $query['pair'] }
      if ([string]::IsNullOrWhiteSpace($projectText)) { throw "缺少 projectRoot，无法让 Codex 规划任务。" }
      if ([string]::IsNullOrWhiteSpace($pair)) { throw "缺少 pair，无法让 Codex 规划任务。" }
      $project = Assert-AllowedProject $projectText
      Assert-AiRelayPairName $pair
      $goal = ([string]$form['goal']).Trim()
      $maxRounds = 3
      if ([string]$form['maxRounds'] -match '^\d+$') { $maxRounds = [int]$form['maxRounds'] }
      if ($maxRounds -lt 1) { $maxRounds = 1 }
      if ($maxRounds -gt 20) { $maxRounds = 20 }
      if ([string]::IsNullOrWhiteSpace($goal)) {
        throw "请填写目标。"
      }
      $pairDir = Get-AiRelayPairDir $project $pair
      if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair 不存在：$pairDir" }
      $pairJson = Read-AiRelayPairJson $pairDir
      $codexSessionId = [string]$pairJson.codexSessionId
      if ([string]::IsNullOrWhiteSpace($codexSessionId)) {
        throw "pair.json 缺少 codexSessionId，请先绑定/重绑 Codex。"
      }
      $goalPath = Join-Path $pairDir 'goal.json'
      $inboxPath = Join-Path $pairDir 'cc-inbox.md'
      $userGoalPath = Join-Path $pairDir 'user-goal.md'
      $planPromptPath = Join-Path $pairDir 'codex-plan-prompt.md'
      $planReplyPath = Join-Path $pairDir 'codex-plan-reply.md'
      Write-AiRelayJson ([ordered]@{
        pairId = $pair
        goal = $goal
        status = 'planned'
        round = 0
        maxRounds = $maxRounds
        startedAt = (Get-Date).ToString('o')
        updatedAt = (Get-Date).ToString('o')
        stopReason = ''
        lastDecision = ''
        lastNextInstruction = ''
      }) $goalPath
      $userGoal = @"
# User Goal - $pair

## Goal
$goal

Max rounds: $maxRounds
"@
      Set-Content -LiteralPath $userGoalPath -Value $userGoal -Encoding utf8
      $context = Read-AiRelayTextFile (Join-Path $pairDir 'context.md')
      $prompt = @"
$context

# 用户目标
$goal

# Codex 规划要求
你是此 pair 的 Codex 指挥线程。请根据用户目标，生成给 Claude Code 的下一轮最小可执行任务。

必须遵守：
- 不修改业务代码。
- 不使用 subagent。
- 不启动 codex-with-cc。
- 不使用 --last。
- 不把完整项目代码塞进 prompt。
- 只给 Claude Code 一个边界清晰、最小化、可执行的任务。
- 如果目标信息不足，让 Claude Code 做只读巡检并返回压缩事实。
- 如果可能与其他 pair 冲突，必须写入风险提醒。

固定输出：
## 给 Claude Code 的任务
写成 Claude Code 可直接执行的任务。

## 规划理由
3-5 条。

## 冲突风险
说明可能冲突或无法判断。

## 额度控制
说明这一轮结束后是否需要回问 Codex。
"@
      Set-Content -LiteralPath $planPromptPath -Value $prompt -Encoding utf8
      $codex = Get-Command codex -ErrorAction SilentlyContinue
      if (-not $codex) { throw "codex CLI not found in PATH." }
      Write-Host ("[{0}] PLAN task project={1} pair={2} codex={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $codexSessionId)
      $oldErrorActionPreference = $ErrorActionPreference
      $oldNativePreference = $null
      $hadNativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
      if ($hadNativePreference) { $oldNativePreference = $PSNativeCommandUseErrorActionPreference }
      try {
        $ErrorActionPreference = 'Continue'
        if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $false }
        $codexOutput = Get-Content -LiteralPath $planPromptPath -Raw -Encoding utf8 | & $codex.Source exec -C $project resume --ignore-user-config -c 'sandbox_mode="read-only"' -o $planReplyPath $codexSessionId - 2>&1 | Out-String
      } finally {
        $ErrorActionPreference = $oldErrorActionPreference
        if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $oldNativePreference }
      }
      $exitCode = $LASTEXITCODE
      Set-Content -LiteralPath (Join-Path $pairDir 'codex-plan.log') -Value $codexOutput -Encoding utf8
      if ($exitCode -ne 0) {
        throw "Codex 规划失败。ExitCode=$exitCode`n$codexOutput"
      }
      $planReply = Read-AiRelayTextFile $planReplyPath
      if ([string]::IsNullOrWhiteSpace($planReply)) {
        $planReply = $codexOutput
      }
      Set-Content -LiteralPath (Join-Path $pairDir 'codex-reply.md') -Value $planReply -Encoding utf8
      $taskMatch = [regex]::Match($planReply, '## 给 Claude Code 的任务\s*([\s\S]*?)(?=\r?\n## |\z)')
      $taskText = if ($taskMatch.Success) { $taskMatch.Groups[1].Value.Trim() } else { $planReply.Trim() }
      if ([string]::IsNullOrWhiteSpace($taskText)) {
        throw "Codex 规划结果为空，无法写入 cc-inbox.md。"
      }
      Set-Content -LiteralPath $inboxPath -Value $taskText -Encoding utf8
      Add-AiRelayLog -PairDir $pairDir -Event 'dashboard-codex-plan' -Detail "Goal: $goal`nMaxRounds=$maxRounds`nCodexSession=$codexSessionId"
      [void](Copy-AiRelayText $taskText)
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Codex 已规划并下发任务' "<p>已更新 goal.json、user-goal.md，并由 Codex 规划后写入 cc-inbox.md。现在可以点击“让 CC 执行并打开终端”。</p><h2>写入 cc-inbox.md</h2><pre>$(Encode-Html $taskText)</pre><h2>Codex 完整回复</h2><pre>$(Encode-Html $planReply)</pre>")
      return
    }

    if ($path -eq '/action/rebind-codex') {
      $form = Get-RequestFormMap $Request
      $projectText = if ($form.ContainsKey('projectRoot') -and -not [string]::IsNullOrWhiteSpace([string]$form['projectRoot'])) { [string]$form['projectRoot'] } else { Decode-Query $query['projectRoot'] }
      $pair = if ($form.ContainsKey('pair') -and -not [string]::IsNullOrWhiteSpace([string]$form['pair'])) { [string]$form['pair'] } else { Decode-Query $query['pair'] }
      if ([string]::IsNullOrWhiteSpace($projectText)) { throw "缺少 projectRoot，无法绑定 Codex session。请刷新面板后重试。" }
      if ([string]::IsNullOrWhiteSpace($pair)) { throw "缺少 pair，无法绑定 Codex session。请刷新面板后重试。" }
      $project = Assert-AllowedProject $projectText
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

    if ($path -eq '/action/codex-terminal') {
      $project = Assert-AllowedProject (Decode-Query $query['projectRoot'])
      $pair = Decode-Query $query['pair']
      Assert-AiRelayPairName $pair
      $pairDir = Get-AiRelayPairDir $project $pair
      $pairJson = Read-AiRelayPairJson $pairDir
      $codexSessionId = [string]$pairJson.codexSessionId
      if ([string]::IsNullOrWhiteSpace($codexSessionId)) {
        throw "pair.json 缺少 codexSessionId，请先绑定/重绑 Codex。"
      }
      $powershell = Get-Command powershell -ErrorAction SilentlyContinue
      if (-not $powershell) { throw "powershell.exe not found." }
      $terminalCommand = @"
`$ErrorActionPreference = 'Continue'
try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
  `$OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {}
Set-Location -LiteralPath '$($project.Replace("'", "''"))'
Write-Host 'Agent Workloop Codex terminal'
Write-Host 'Pair: $($pair.Replace("'", "''"))'
Write-Host 'Project: $($project.Replace("'", "''"))'
Write-Host 'Codex session: $($codexSessionId.Replace("'", "''"))'
Write-Host ''
codex resume -C '$($project.Replace("'", "''"))' --sandbox read-only '$($codexSessionId.Replace("'", "''"))'
Write-Host ''
Read-Host 'Codex 终端已退出，按 Enter 关闭窗口'
"@
      $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($terminalCommand))
      Start-Process -FilePath $powershell.Source -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        $encodedCommand
      ) -WorkingDirectory $project -WindowStyle Normal | Out-Null
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Codex 终端已打开' "<p>已打开绑定的 Codex session。</p><pre>$(Encode-Html $codexSessionId)</pre>")
      return
    }

    if ($path -eq '/action/rebind-cc') {
      $form = Get-RequestFormMap $Request
      $projectText = if ($form.ContainsKey('projectRoot') -and -not [string]::IsNullOrWhiteSpace([string]$form['projectRoot'])) { [string]$form['projectRoot'] } else { Decode-Query $query['projectRoot'] }
      $pair = if ($form.ContainsKey('pair') -and -not [string]::IsNullOrWhiteSpace([string]$form['pair'])) { [string]$form['pair'] } else { Decode-Query $query['pair'] }
      if ([string]::IsNullOrWhiteSpace($projectText)) { throw "缺少 projectRoot，无法绑定 Claude Code session。请刷新面板后重试。" }
      if ([string]::IsNullOrWhiteSpace($pair)) { throw "缺少 pair，无法绑定 Claude Code session。请刷新面板后重试。" }
      $project = Assert-AllowedProject $projectText
      $ccSessionId = ([string]$form['ccSessionId']).Trim()
      Assert-AiRelayPairName $pair
      $ccInitOutput = ''
      if ([string]::IsNullOrWhiteSpace($ccSessionId)) {
        $ccSessionId = ''
        $ccInitOutput = 'Claude Code session id was cleared. The dashboard runner will open a new native Claude Code terminal when executing this pair.'
      }
      if (-not [string]::IsNullOrWhiteSpace($ccSessionId) -and $ccSessionId -notmatch '^[0-9a-fA-F-]{20,}$') {
        throw "Claude Code Session ID 格式看起来不正确：$ccSessionId"
      }
      $ccSessionForLog = if ([string]::IsNullOrWhiteSpace($ccSessionId)) { '<new-terminal-on-run>' } else { $ccSessionId }
      Write-Host ("[{0}] REBIND cc project={1} pair={2} session={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $ccSessionForLog)
      Set-WorkloopCcSessionId -Project $project -Pair $pair -CcSessionId $ccSessionId
      if ($ccInitOutput) {
        Set-Content -LiteralPath (Join-Path (Get-AiRelayPairDir $project $pair) 'cc-session-init.log') -Value $ccInitOutput -Encoding utf8
      }
      $ccBindLabel = if ([string]::IsNullOrWhiteSpace($ccSessionId)) { '未预绑定；执行时打开新的 Claude Code 原生终端' } else { $ccSessionId }
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Claude Code 绑定已更新' "<p>Pair 的 Claude Code 执行方式已更新。</p><p>Claude Code session: <code>$(Encode-Html $ccBindLabel)</code></p>")
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
      $activeStatus = Get-ActiveCcRunnerStatus -StatusPath $statusPath
      if ($activeStatus) {
        Write-Host ("[{0}] SKIP cc-runner already active project={1} pair={2} pid={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $activeStatus.processId)
        Write-HttpText -Response $Response -Text (New-CcRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
        return
      }
      $route = Get-WorkloopRoute -PairDir $pairDir
      if ($route.Action -eq 'send-report') {
        Write-Host ("[{0}] ROUTE cc-runner to workloop report project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
        $output = Invoke-Captured {
          Push-Location $project
          try { & "$PSScriptRoot\ai-workloop.ps1" $pair } finally { Pop-Location }
        }
        Write-HttpText -Response $Response -Text (New-ResultHtml '已按状态机送审' "<p>$(Encode-Html $route.Message)</p><pre>$(Encode-Html $output)</pre>")
        return
      }
      if ($route.Action -eq 'idle') {
        Write-Host ("[{0}] ROUTE cc-runner idle project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
        Write-HttpText -Response $Response -Text (New-ResultHtml '无可执行任务' "<p>$(Encode-Html $route.Message)</p><p>请先让 Codex 规划任务，或让 CC 完成任务后写入 cc-report.md。</p>")
        return
      }
      $runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
      $stdoutPath = Join-Path $pairDir "cc-runner-process-$runId.stdout.log"
      $stderrPath = Join-Path $pairDir "cc-runner-process-$runId.stderr.log"
      Write-AiRelayJson ([ordered]@{
        pairId = $pair
        projectRoot = $project
        status = 'queued'
        message = "已收到面板请求，按状态机路由：$($route.Message)"
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
try {
Set-Location -LiteralPath '$($project.Replace("'", "''"))'
Write-Host 'Agent Workloop CC runner'
Write-Host 'Pair: $($pair.Replace("'", "''"))'
Write-Host 'Project: $($project.Replace("'", "''"))'
Write-Host 'Mode: Claude Code native terminal'
Write-Host ''
`$pairDir = '$($pairDir.Replace("'", "''"))'
`$pairJsonPath = Join-Path `$pairDir 'pair.json'
`$sourcePath = '$([string]$route.SourcePath -replace "'", "''")'
`$readPath = '$([string]$route.ReadPath -replace "'", "''")'
`$sourceLabel = '$([string]$route.Source -replace "'", "''")'
`$statusPath = Join-Path `$pairDir 'cc-runner-status.json'
`$pairJson = Get-Content -LiteralPath `$pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
`$ccSessionId = [string]`$pairJson.ccSessionId
`$sourceText = Get-Content -LiteralPath `$sourcePath -Raw -Encoding utf8
if ([string]::IsNullOrWhiteSpace(`$sourceText)) {
  Write-Host 'cc-inbox.md 为空，没有可执行任务。' -ForegroundColor Yellow
  Read-Host '按 Enter 关闭窗口'
  exit 1
}
`$status = [ordered]@{
  pairId = '$($pair.Replace("'", "''"))'
  projectRoot = '$($project.Replace("'", "''"))'
  status = 'running'
  message = "已打开 Claude Code 原生终端执行 `$sourceLabel。"
  exitCode = 0
  outputPath = '$($runnerOutputPath.Replace("'", "''"))'
  streamPath = '$($runnerStreamPath.Replace("'", "''"))'
  stdoutPath = '$($stdoutPath.Replace("'", "''"))'
  stderrPath = '$($stderrPath.Replace("'", "''"))'
  updatedAt = (Get-Date).ToString('o')
  processId = `$PID
}
`$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath `$statusPath -Encoding utf8
if (-not [string]::IsNullOrWhiteSpace(`$readPath)) {
  try { Set-Content -LiteralPath `$readPath -Value `$sourceText -Encoding utf8 } catch {}
}
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
if ([string]::IsNullOrWhiteSpace(`$ccSessionId)) {
  Write-Host '没有预绑定 Claude Code session，将打开新的 Claude Code 原生终端。'
} else {
  Write-Host "Resuming Claude Code session: `$ccSessionId"
}
Write-Host '下面是 Claude Code 原生终端输出。'
Write-Host ''
if ([string]::IsNullOrWhiteSpace(`$ccSessionId)) {
  & `$claude.Source --name 'workloop-$($pair.Replace("'", "''"))' --permission-mode default `$prompt
} else {
  & `$claude.Source --resume `$ccSessionId --permission-mode default `$prompt
  if (`$LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '恢复 Claude Code session 失败，可能是这个 session id 不在本机 Claude 历史里。现在改为打开新的 Claude Code 原生终端执行同一任务。' -ForegroundColor Yellow
    & `$claude.Source --name 'workloop-$($pair.Replace("'", "''"))' --permission-mode default `$prompt
  }
}
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
} catch {
  Write-Host "CC runner wrapper failed: `$(`$_.Exception.Message)" -ForegroundColor Red
  try {
    if (`$status -and `$statusPath) {
      `$status.status = 'failed'
      `$status.exitCode = 1
      `$status.message = "CC runner wrapper failed: `$(`$_.Exception.Message)"
      `$status.updatedAt = (Get-Date).ToString('o')
      `$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath `$statusPath -Encoding utf8
    }
  } catch {}
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
        message = "已启动 Claude Code 原生终端，按状态机执行 $($route.Source)，等待终端写入运行状态。"
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

    if ($path -eq '/action/summary') {
      $analyzer = [string]$query['analyzer']
      if ([string]::IsNullOrWhiteSpace($analyzer)) { $analyzer = 'cc' }
      if ($analyzer -notin @('cc','codex','local')) { throw "不支持的总结分析方式：$analyzer" }
      Write-Host ("[{0}] RUN summary project={1} pair={2} analyzer={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $analyzer)
      $output = Invoke-Captured {
        Push-Location $project
        try { & "$PSScriptRoot\ai-workloop-summary.ps1" -Pair $pair -Analyzer $analyzer -Format both -Open } finally { Pop-Location }
      }
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Pair 总结生成结果' "<pre>$(Encode-Html $output)</pre>")
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
