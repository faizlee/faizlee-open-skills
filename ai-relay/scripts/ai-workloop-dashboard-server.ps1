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

function Write-HttpJson {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [object]$Data,
    [int]$StatusCode = 200
  )
  $json = $Data | ConvertTo-Json -Depth 8
  Write-HttpText -Response $Response -Text $json -ContentType 'application/json; charset=utf-8' -StatusCode $StatusCode
}

function Encode-Html {
  param([string]$Text)
  [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function New-StatusInsightPanelHtml {
  param(
    [object]$Insight,
    [string]$Title = '当前解释'
  )
  if (-not $Insight) { return '' }
  $tone = if ($Insight.Tone) { [string]$Insight.Tone } else { 'unknown' }
  @"
    <section class="insight insight-$tone">
      <h2>$(Encode-Html $Title)</h2>
      <strong>$(Encode-Html $Insight.Label)</strong>
      <p>$(Encode-Html $Insight.Detail)</p>
      <p><b>下一步：</b>$(Encode-Html $Insight.NextAction)</p>
    </section>
"@
}

function ConvertTo-SessionFileSizeLabel {
  param([long]$Size)
  if ($Size -ge 1MB) { return ('{0:N1}MB' -f ($Size / 1MB)) }
  if ($Size -ge 1KB) { return ('{0:N1}KB' -f ($Size / 1KB)) }
  return "$Size B"
}

function Get-SessionTextFromPayload {
  param($Payload)
  if (-not $Payload) { return '' }
  $content = $Payload.content
  if ($content -is [string]) { return $content.Trim() }
  if ($content -is [array]) {
    $parts = @()
    foreach ($item in $content) {
      if ($item -and $item.text) { $parts += [string]$item.text }
    }
    return (($parts -join "`n").Trim())
  }
  return ''
}

function Ensure-WorkloopGoalFromPairTask {
  param(
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$Pair,
    [int]$MaxRounds = 10
  )

  if ($MaxRounds -lt 1) { $MaxRounds = 1 }
  if ($MaxRounds -gt 20) { $MaxRounds = 20 }

  $pairDir = Get-AiRelayPairDir $Project $Pair
  if (-not (Test-Path -LiteralPath $pairDir)) { return $false }

  $goalPath = Join-Path $pairDir 'goal.json'
  if (Test-Path -LiteralPath $goalPath) { return $false }

  $pairJsonPath = Join-Path $pairDir 'pair.json'
  if (-not (Test-Path -LiteralPath $pairJsonPath)) { return $false }

  try {
    $pairJson = Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
  } catch {
    return $false
  }

  $task = [string]$pairJson.task
  if ([string]::IsNullOrWhiteSpace($task)) { return $false }

  $now = (Get-Date).ToString('o')
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    goal = $task.Trim()
    status = 'planned'
    round = 0
    maxRounds = $MaxRounds
    startedAt = $now
    updatedAt = $now
    stopReason = ''
    lastDecision = ''
    lastNextInstruction = ''
  }) $goalPath

  $userGoalPath = Join-Path $pairDir 'user-goal.md'
  if (-not (Test-Path -LiteralPath $userGoalPath)) {
    $userGoal = @"
# User Goal - $Pair

## Goal
$($task.Trim())

Max rounds: $MaxRounds
"@
    Set-Content -LiteralPath $userGoalPath -Value $userGoal -Encoding utf8
  }

  Add-AiRelayLog -PairDir $pairDir -Event 'workloop-goal-bootstrap' -Detail "goal.json was created from pair.json task. MaxRounds=$MaxRounds"
  return $true
}

function Get-CodexRelaySessions {
  $sessionsRoot = Join-Path $workloopHome '.codex\sessions'
  $boundBySession = @{}
  foreach ($project in (Get-AllowedProjects)) {
    $pairsRoot = Join-Path (Join-Path $project '.ai-relay') 'pairs'
    if (-not (Test-Path -LiteralPath $pairsRoot)) { continue }
    foreach ($pairDir in (Get-ChildItem -LiteralPath $pairsRoot -Directory -ErrorAction SilentlyContinue)) {
      $pairJsonPath = Join-Path $pairDir.FullName 'pair.json'
      if (-not (Test-Path -LiteralPath $pairJsonPath)) { continue }
      try { $pairJson = Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { continue }
      $sessionId = [string]$pairJson.codexSessionId
      if ([string]::IsNullOrWhiteSpace($sessionId)) { continue }
      if (-not $boundBySession.ContainsKey($sessionId)) { $boundBySession[$sessionId] = @() }
      $boundBySession[$sessionId] += [pscustomobject]@{
        pairId = $pairDir.Name
        projectRoot = $project
        task = [string]$pairJson.task
        role = [string]$pairJson.role
        boundAt = [string]$pairJson.boundAt
      }
    }
  }
  if (-not (Test-Path -LiteralPath $sessionsRoot)) {
    return [pscustomobject]@{
      success = $true
      root = $sessionsRoot
      count = 0
      sessions = @()
    }
  }
  $files = @(Get-ChildItem -LiteralPath $sessionsRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 100)
  $sessions = @()
  foreach ($file in $files) {
    $id = ''
    $cwd = ''
    $source = ''
    $originator = ''
    $createdAt = ''
    $firstUserMessage = ''
    $firstNonEnvUserMessage = ''
    try {
      foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $event = $line | ConvertFrom-Json } catch { continue }
        if ([string]$event.type -eq 'session_meta') {
          $payload = $event.payload
          if ($payload) {
            if ($payload.id) { $id = [string]$payload.id }
            if ($payload.cwd) { $cwd = [string]$payload.cwd }
            if ($payload.source) { $source = [string]$payload.source }
            if ($payload.originator) { $originator = [string]$payload.originator }
            if ($payload.timestamp) { $createdAt = [string]$payload.timestamp }
            elseif ($event.timestamp) { $createdAt = [string]$event.timestamp }
          }
          continue
        }
        $payload = $event.payload
        if (-not $payload -or [string]$payload.role -ne 'user') { continue }
        $messageText = Get-SessionTextFromPayload -Payload $payload
        if ([string]::IsNullOrWhiteSpace($messageText)) { continue }
        if (-not $firstUserMessage) { $firstUserMessage = $messageText }
        if (-not $firstNonEnvUserMessage -and -not ($messageText.StartsWith('<environment_context>') -and $messageText.TrimEnd().EndsWith('</environment_context>'))) {
          $firstNonEnvUserMessage = $messageText
        }
        if ($id -and $firstNonEnvUserMessage) { break }
      }
    } catch {
      continue
    }
    if (-not $id) { continue }
    $title = @($firstNonEnvUserMessage, $firstUserMessage, $id) |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Select-Object -First 1
    $title = ([string]$title -replace '\s+', ' ').Trim()
    if ($title.Length -gt 160) { $title = $title.Substring(0, 160) }
    $boundPairs = if ($boundBySession.ContainsKey($id)) { @($boundBySession[$id]) } else { @() }
    $boundPairCount = @($boundPairs).Count
    $sessions += [pscustomobject]@{
      id = $id
      cwd = $cwd
      source = $source
      originator = $originator
      createdAt = if ($createdAt) { $createdAt } else { $file.CreationTime.ToString('o') }
      lastWriteAt = $file.LastWriteTime.ToString('o')
      size = $file.Length
      sizeLabel = ConvertTo-SessionFileSizeLabel -Size $file.Length
      title = $title
      path = $file.FullName
      bound = ($boundPairCount -gt 0)
      boundPairs = $boundPairs
      boundPairCount = $boundPairCount
    }
  }
  [pscustomobject]@{
    success = $true
    root = $sessionsRoot
    count = $sessions.Count
    sessions = @($sessions)
  }
}

function Get-ClaudeRelaySessions {
  $projectsRoot = Join-Path $workloopHome '.claude\projects'
  $boundBySession = @{}
  $pairOnlySessions = @()
  $pairSeen = @{}
  foreach ($project in (Get-AllowedProjects)) {
    $pairsRoot = Join-Path (Join-Path $project '.ai-relay') 'pairs'
    if (-not (Test-Path -LiteralPath $pairsRoot)) { continue }
    foreach ($pairDir in (Get-ChildItem -LiteralPath $pairsRoot -Directory -ErrorAction SilentlyContinue)) {
      $pairJsonPath = Join-Path $pairDir.FullName 'pair.json'
      if (-not (Test-Path -LiteralPath $pairJsonPath)) { continue }
      try { $pairJson = Get-Content -LiteralPath $pairJsonPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { continue }
      $sessionId = [string]$pairJson.ccSessionId
      $sessionName = [string]$pairJson.ccSessionName
      $key = if ($sessionId) { $sessionId } else { $sessionName }
      if ([string]::IsNullOrWhiteSpace($key)) { continue }
      if (-not $boundBySession.ContainsKey($key)) { $boundBySession[$key] = @() }
      $boundBySession[$key] += [pscustomobject]@{
        pairId = $pairDir.Name
        projectRoot = $project
        task = [string]$pairJson.task
        boundAt = [string]$pairJson.boundAt
      }
      if (-not $pairSeen.ContainsKey($key)) {
        $pairSeen[$key] = $true
        $pairOnlySessions += [pscustomobject]@{
          id = $sessionId
          name = $sessionName
          title = if ($sessionName) { $sessionName } elseif ($sessionId) { $sessionId } else { $pairDir.Name }
          cwd = $project
          projectRoot = $project
          gitBranch = ''
          lastWriteAt = ''
          size = 0
          sizeLabel = ''
          path = $pairJsonPath
          source = 'pair.json'
          bound = $true
          boundPairs = @($boundBySession[$key])
          boundPairCount = @($boundBySession[$key]).Count
        }
      }
    }
  }

  if (-not (Test-Path -LiteralPath $projectsRoot)) {
    return [pscustomobject]@{
      success = $true
      root = $projectsRoot
      count = $pairOnlySessions.Count
      sessions = @($pairOnlySessions)
    }
  }

  $sessions = @()
  $files = @(Get-ChildItem -LiteralPath $projectsRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/]subagents[\\/]' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 100)
  $fileSessionIds = @{}
  foreach ($file in $files) {
    $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $sessionName = $sessionId
    $cwd = ''
    $gitBranch = ''
    $createdAt = ''
    $title = ''
    $aiTitle = ''
    try {
      $lineCount = 0
      foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
        $lineCount += 1
        if ($lineCount -gt 400) { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $event = $line | ConvertFrom-Json } catch { continue }
        if ([string]$event.type -eq 'ai-title' -and $event.aiTitle) {
          $aiTitle = [string]$event.aiTitle
        }
        if ($event.sessionId) { $sessionId = [string]$event.sessionId }
        if ($event.cwd) { $cwd = [string]$event.cwd }
        if ($event.gitBranch) { $gitBranch = [string]$event.gitBranch }
        if ($event.timestamp -and -not $createdAt) { $createdAt = [string]$event.timestamp }
        if (-not $title -and [string]$event.type -eq 'user' -and $event.message) {
          $messageText = Get-SessionTextFromPayload -Payload $event.message
          if (
            -not [string]::IsNullOrWhiteSpace($messageText) -and
            -not $messageText.StartsWith('<command-message>') -and
            -not $messageText.StartsWith('<command-name>') -and
            -not $messageText.StartsWith('<local-command-caveat>')
          ) {
            $title = $messageText
          }
        }
        if ($sessionId -and $cwd -and $aiTitle) { break }
      }
    } catch {
      continue
    }
    if (-not $sessionId) { continue }
    if (-not [string]::IsNullOrWhiteSpace($aiTitle)) { $title = $aiTitle }
    if ([string]::IsNullOrWhiteSpace($title)) { $title = $sessionName }
    $title = ([string]$title -replace '\s+', ' ').Trim()
    if ($title.Length -gt 160) { $title = $title.Substring(0, 160) }
    $boundPairs = if ($boundBySession.ContainsKey($sessionId)) { @($boundBySession[$sessionId]) } else { @() }
    $boundPairCount = @($boundPairs).Count
    $fileSessionIds[$sessionId] = $true
    $sessions += [pscustomobject]@{
      id = $sessionId
      name = $sessionName
      title = $title
      cwd = $cwd
      projectRoot = $cwd
      gitBranch = $gitBranch
      createdAt = if ($createdAt) { $createdAt } else { $file.CreationTime.ToString('o') }
      lastWriteAt = $file.LastWriteTime.ToString('o')
      size = $file.Length
      sizeLabel = ConvertTo-SessionFileSizeLabel -Size $file.Length
      path = $file.FullName
      source = 'claude-project-jsonl'
      bound = ($boundPairCount -gt 0)
      boundPairs = $boundPairs
      boundPairCount = $boundPairCount
    }
  }

  foreach ($item in $pairOnlySessions) {
    if ($item.id -and $fileSessionIds.ContainsKey([string]$item.id)) { continue }
    $sessions += $item
  }

  [pscustomobject]@{
    success = $true
    root = $projectsRoot
    count = $sessions.Count
    sessions = @($sessions | Sort-Object @{ Expression = {
      if ($_.lastWriteAt) {
        try { [datetime]::Parse([string]$_.lastWriteAt) } catch { [datetime]::MinValue }
      } else { [datetime]::MinValue }
    }; Descending = $true })
  }
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

function New-AutoPostHtml {
  param(
    [string]$Title,
    [string]$Message,
    [string]$ActionUrl,
    [hashtable]$Fields,
    [string]$FallbackUrl = '/'
  )
  $inputs = [System.Text.StringBuilder]::new()
  foreach ($key in $Fields.Keys) {
    [void]$inputs.AppendLine("<input type=""hidden"" name=""$(Encode-Html $key)"" value=""$(Encode-Html ([string]$Fields[$key]))"">")
  }
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
    button { border:1px solid #176b5d; border-radius:6px; background:#e7f2ed; color:#176b5d; padding:8px 12px; font:inherit; cursor:pointer; }
    a { color: #176b5d; }
  </style>
</head>
<body>
  <main>
    <h1>$(Encode-Html $Title)</h1>
    <pre>$(Encode-Html $Message)</pre>
    <form method="post" action="$(Encode-Html $ActionUrl)">
      $($inputs.ToString())
      <button type="submit">如果没有自动继续，点这里</button>
    </form>
    <p><a href="$(Encode-Html $FallbackUrl)">查看状态</a> · <a href="/">返回 Dashboard</a></p>
  </main>
  <script>setTimeout(() => document.querySelector('form').submit(), 150);</script>
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
  function Get-JsonPropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
  }
  function Convert-StreamValueToText {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [array]) {
      $parts = @()
      foreach ($item in $Value) {
        $text = Convert-StreamValueToText $item
        if ($text) { $parts += $text }
      }
      return ($parts -join "`n")
    }
    $text = Get-JsonPropertyValue $Value 'text'
    if ($text) { return [string]$text }
    $content = Get-JsonPropertyValue $Value 'content'
    if ($content) { return Convert-StreamValueToText $content }
    $message = Get-JsonPropertyValue $Value 'message'
    if ($message) { return Convert-StreamValueToText $message }
    return ''
  }
  function Convert-CcStreamToTimelineHtml {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
      return '<p class="muted">暂无 stream-json 文件。</p>'
    }
    $lines = @(Get-Content -LiteralPath $Path -Tail 500 -Encoding utf8 -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) { return '<p class="muted">stream-json 文件为空。</p>' }
    $events = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try { $event = $line | ConvertFrom-Json } catch { continue }
      $type = [string](Get-JsonPropertyValue $event 'type')
      if ([string]::IsNullOrWhiteSpace($type)) { $type = 'event' }
      $class = 'event-system'
      $title = $type
      $detail = ''

      $subtype = [string](Get-JsonPropertyValue $event 'subtype')
      $name = [string](Get-JsonPropertyValue $event 'name')
      $toolName = [string](Get-JsonPropertyValue $event 'tool_name')
      $status = [string](Get-JsonPropertyValue $event 'status')
      $message = Get-JsonPropertyValue $event 'message'
      $result = Get-JsonPropertyValue $event 'result'
      $input = Get-JsonPropertyValue $event 'input'
      $delta = Get-JsonPropertyValue $event 'delta'
      $contentBlock = Get-JsonPropertyValue $event 'content_block'

      if ($type -match 'tool|Tool' -or $name -or $toolName) {
        $class = 'event-tool'
        $title = if ($toolName) { "工具：$toolName" } elseif ($name) { "工具：$name" } else { $type }
        if ($input) {
          try { $detail = ($input | ConvertTo-Json -Compress -Depth 5) } catch { $detail = [string]$input }
        }
      } elseif ($type -match 'result|Result') {
        $class = 'event-result'
        $title = '工具结果'
        $detail = Convert-StreamValueToText $result
      } elseif ($type -match 'assistant|message|content_block') {
        $class = 'event-assistant'
        $title = if ($subtype) { "$type / $subtype" } else { $type }
        $detail = Convert-StreamValueToText $message
        if (-not $detail) { $detail = Convert-StreamValueToText $delta }
        if (-not $detail) { $detail = Convert-StreamValueToText $contentBlock }
      } else {
        $class = 'event-system'
        $title = if ($subtype) { "$type / $subtype" } elseif ($status) { "$type / $status" } else { $type }
        $detail = Convert-StreamValueToText $message
      }
      if ([string]::IsNullOrWhiteSpace($detail) -and $type -match 'delta') { continue }
      if ($detail.Length -gt 700) { $detail = $detail.Substring(0, 700) + '...' }
      $events.Add("<li class=""stream-event $class""><strong>$(Encode-Html $title)</strong><span>$(Encode-Html $detail)</span></li>")
      if ($events.Count -ge 120) { break }
    }
    if ($events.Count -eq 0) { return '<p class="muted">stream-json 暂无可读事件；可能 Claude CLI 尚未输出结构化事件。</p>' }
    return "<ol class=""stream-events"">$($events -join "`n")</ol>"
  }
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
  $reportTime = $null
  if (Test-Path -LiteralPath $reportPath) {
    $reportTime = (Get-Item -LiteralPath $reportPath).LastWriteTime
  }
  $statusTime = $null
  if ($updatedAt) {
    try { $statusTime = [datetime]::Parse($updatedAt) } catch { $statusTime = $null }
  }
  $processAlive = $false
  if ($processId -match '^\d+$') {
    $processAlive = [bool](Get-Process -Id ([int]$processId) -ErrorAction SilentlyContinue)
  }
  if ($statusText -in @('queued','started','running') -and $processId -and -not $processAlive) {
    $statusText = 'stale'
    if ($reportTime -and ((-not $statusTime) -or ($reportTime -ge $statusTime))) {
      $message = "$message`n`n检测到 runner 进程已经不存在，但 cc-report.md 已在 runner 启动后更新。此轮很可能已经写完报告，只是状态文件没有回写完成。下一步通常是返回 Dashboard，执行 /workloop 将报告送 Codex 审核。"
    } else {
      $message = "$message`n`n检测到 runner 进程已经不存在，但状态文件仍是 running。stderr 为空时请看输出片段、cc-report.md 更新时间和控制器窗口；必要时重新执行。"
    }
  }
  $output = ''
  if (Test-Path -LiteralPath $outputPath) {
    $output = Get-Content -LiteralPath $outputPath -Raw -Encoding utf8
    if ($output.Length -gt 12000) {
      $output = $output.Substring($output.Length - 12000)
    }
  }
  if ([string]::IsNullOrWhiteSpace($output)) {
    if ($statusText -eq 'stale' -and $reportTime -and ((-not $statusTime) -or ($reportTime -ge $statusTime))) {
      $output = "没有捕获到 Claude stdout，但 cc-report.md 已更新。`n`n这通常表示 Claude Code 原生终端完成了任务并写入报告，但 runner 状态文件没有最终回写。请打开报告确认内容，或返回 Dashboard 执行 /workloop 送审。"
    } else {
      $output = "暂无 Claude stdout 输出。Claude CLI 的 --print 模式可能在任务完成后才一次性写入结果。`n`n如果状态仍是 running，请继续等待；也可以查看控制器窗口里的 cc-runner started pid。"
    }
  }
  $stderr = ''
  if (Test-Path -LiteralPath $runnerStderrPath) {
    $stderr = Get-Content -LiteralPath $runnerStderrPath -Raw -Encoding utf8
    if ($stderr.Length -gt 6000) {
      $stderr = $stderr.Substring($stderr.Length - 6000)
    }
  }
  if ([string]::IsNullOrWhiteSpace($stderr)) {
    if ($statusText -eq 'stale' -and $reportTime -and ((-not $statusTime) -or ($reportTime -ge $statusTime))) {
      $stderr = 'stderr 为空。结合 cc-report.md 已更新判断，这更像是状态回写缺失，不是 stderr 报错。'
    } else {
      $stderr = 'stderr 为空。'
    }
  }
  $reportInfo = if (Test-Path -LiteralPath $reportPath) {
    $item = Get-Item -LiteralPath $reportPath
    "cc-report.md 更新时间：$($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
  } else {
    'cc-report.md 尚不存在。'
  }
  $ccInsight = Get-AiRelayStatusInsight -Kind 'cc' -Status $statusText -ProcessAlive $processAlive -Message $message -HasOutput (-not [string]::IsNullOrWhiteSpace($output)) -HasStderr (-not [string]::IsNullOrWhiteSpace($stderr) -and $stderr -ne 'stderr 为空。') -HasReport (Test-Path -LiteralPath $reportPath)
  $ccInsightHtml = New-StatusInsightPanelHtml -Insight $ccInsight
  $streamTimelineHtml = Convert-CcStreamToTimelineHtml -Path $streamPath
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
    .insight { border:1px solid #d8ddd8; border-left-width:5px; border-radius:8px; padding:12px 14px; margin:14px 0; background:#fbfcfa; }
    .insight h2 { margin:0 0 8px; font-size:16px; }
    .insight strong { display:block; margin-bottom:6px; }
    .insight p { margin:5px 0; }
    .insight-running { border-left-color:#176b5d; }
    .insight-warn { border-left-color:#d08a2f; background:#fffaf0; }
    .insight-bad { border-left-color:#b76a6a; background:#fff4f4; }
    .insight-good { border-left-color:#7ca88f; background:#f2fbf5; }
    .muted { color:#65717d; }
    dl { display:grid; grid-template-columns:160px 1fr; gap:8px 12px; }
    dt { color:#65717d; }
    dd { margin:0; overflow-wrap:anywhere; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; background: #f5f6f2; border: 1px solid #e4e6df; border-radius: 6px; padding: 12px; }
    .stream-events { list-style:none; padding:0; margin:12px 0; display:grid; gap:8px; }
    .stream-event { border:1px solid #d8ddd8; border-left-width:5px; border-radius:8px; padding:9px 11px; background:#fff; }
    .stream-event strong { display:block; margin-bottom:4px; }
    .stream-event span { display:block; white-space:pre-wrap; overflow-wrap:anywhere; color:#46525f; }
    .event-system { border-left-color:#8a927f; }
    .event-assistant { border-left-color:#7b8fb3; background:#f4f7ff; }
    .event-tool { border-left-color:#d08a2f; background:#fffaf0; }
    .event-result { border-left-color:#7ca88f; background:#f2fbf5; }
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
    $ccInsightHtml
    $stopForm
    $runForm
    <h2>实时事件流</h2>
    $streamTimelineHtml
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

function New-CodexPlanStatusHtml {
  param(
    [string]$Project,
    [string]$Pair,
    [string]$BaseUrl
  )
  $pairDir = Get-AiRelayPairDir $Project $Pair
  $statusPath = Join-Path $pairDir 'codex-plan-status.json'
  $replyPath = Join-Path $pairDir 'codex-plan-reply.md'
  $inboxPath = Join-Path $pairDir 'cc-inbox.md'
  $logPath = Join-Path $pairDir 'codex-plan.log'
  $status = $null
  if (Test-Path -LiteralPath $statusPath) {
    try { $status = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { $status = $null }
  }
  $statusText = if ($status -and $status.status) { [string]$status.status } else { 'unknown' }
  $message = if ($status -and $status.message) { [string]$status.message } else { '尚未写入规划状态。' }
  $updatedAt = if ($status -and $status.updatedAt) { [string]$status.updatedAt } else { '' }
  $processId = if ($status -and $status.processId) { [string]$status.processId } else { '' }
  $processAlive = $false
  if ($processId -match '^\d+$') {
    $processAlive = [bool](Get-Process -Id ([int]$processId) -ErrorAction SilentlyContinue)
  }
  if ($statusText -eq 'running' -and $processId -and -not $processAlive) {
    $statusText = 'stale'
    $message = "$message`n`n检测到 Codex planner 进程已经不存在，但状态仍是 running。请查看日志和 cc-inbox.md。"
  }
  $log = Read-AiRelayTextFile $logPath
  if ($log.Length -gt 8000) { $log = $log.Substring($log.Length - 8000) }
  if ([string]::IsNullOrWhiteSpace($log)) { $log = '暂无 codex-plan.log 输出。请查看前台 Codex planner 终端。' }
  $reply = Read-AiRelayTextFile $replyPath
  if ($reply.Length -gt 8000) { $reply = $reply.Substring($reply.Length - 8000) }
  if ([string]::IsNullOrWhiteSpace($reply)) { $reply = '暂无 Codex 规划回复。' }
  $inbox = Read-AiRelayTextFile $inboxPath
  if ($inbox.Length -gt 5000) { $inbox = $inbox.Substring($inbox.Length - 5000) }
  if ([string]::IsNullOrWhiteSpace($inbox)) { $inbox = 'cc-inbox.md 暂无内容。' }
  $planInsight = Get-AiRelayStatusInsight -Kind 'codex-plan' -Status $statusText -ProcessAlive $processAlive -Message $message -HasOutput (-not [string]::IsNullOrWhiteSpace($log) -and $log -ne '暂无 codex-plan.log 输出。请查看前台 Codex planner 终端。') -HasReply (-not [string]::IsNullOrWhiteSpace($reply) -and $reply -ne '暂无 Codex 规划回复。') -HasInbox (-not [string]::IsNullOrWhiteSpace($inbox) -and $inbox -ne 'cc-inbox.md 暂无内容。')
  $planInsightHtml = New-StatusInsightPanelHtml -Insight $planInsight
  $projectArg = [System.Uri]::EscapeDataString($Project)
  $pairArg = [System.Uri]::EscapeDataString($Pair)
  $refreshUrl = "$($BaseUrl.TrimEnd('/'))/status/codex-plan?projectRoot=$projectArg&pair=$pairArg"
  $refresh = if ($statusText -in @('queued','started','running','unknown')) {
    "<meta http-equiv='refresh' content='2;url=$(Encode-Html $refreshUrl)'>"
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
  <title>Codex 规划状态</title>
  <style>
    body { font-family:"Segoe UI",system-ui,sans-serif; margin:24px; color:#1f2933; background:#f7f7f4; }
    main { max-width:980px; margin:0 auto; background:#fff; border:1px solid #d8ddd8; border-radius:8px; padding:18px; }
    h1 { margin-top:0; font-size:22px; }
    .badge { display:inline-block; border:1px solid #d8ddd8; border-radius:999px; padding:4px 10px; background:#f5f6f2; }
    .insight { border:1px solid #d8ddd8; border-left-width:5px; border-radius:8px; padding:12px 14px; margin:14px 0; background:#fbfcfa; }
    .insight h2 { margin:0 0 8px; font-size:16px; }
    .insight strong { display:block; margin-bottom:6px; }
    .insight p { margin:5px 0; }
    .insight-running { border-left-color:#176b5d; }
    .insight-warn { border-left-color:#d08a2f; background:#fffaf0; }
    .insight-bad { border-left-color:#b76a6a; background:#fff4f4; }
    .insight-good { border-left-color:#7ca88f; background:#f2fbf5; }
    dl { display:grid; grid-template-columns:150px 1fr; gap:8px 12px; }
    dt { color:#65717d; }
    dd { margin:0; overflow-wrap:anywhere; }
    pre { white-space:pre-wrap; overflow-wrap:anywhere; background:#f5f6f2; border:1px solid #e4e6df; border-radius:6px; padding:12px; }
    a { color:#176b5d; }
  </style>
</head>
<body>
  <main>
    <h1>Codex 规划状态 <span class="badge">$(Encode-Html $statusText)</span></h1>
    <dl>
      <dt>Pair</dt><dd>$(Encode-Html $Pair)</dd>
      <dt>项目</dt><dd>$(Encode-Html $Project)</dd>
      <dt>状态说明</dt><dd>$(Encode-Html $message)</dd>
      <dt>更新时间</dt><dd>$(Encode-Html $updatedAt)</dd>
      <dt>进程 ID</dt><dd>$(Encode-Html $processId)</dd>
      <dt>日志</dt><dd>$(Encode-Html $logPath)</dd>
    </dl>
    $planInsightHtml
    <h2>Codex 日志片段</h2>
    <pre>$(Encode-Html $log)</pre>
    <h2>Codex 完整回复片段</h2>
    <pre>$(Encode-Html $reply)</pre>
    <h2>写入 cc-inbox.md 的任务片段</h2>
    <pre>$(Encode-Html $inbox)</pre>
    <p><a href="$(Encode-Html $refreshUrl)">手动刷新</a> · <a href="/">返回 Dashboard</a></p>
  </main>
</body>
</html>
"@
}

function New-WorkloopRunnerStatusHtml {
  param(
    [string]$Project,
    [string]$Pair,
    [string]$BaseUrl
  )
  $pairDir = Get-AiRelayPairDir $Project $Pair
  $statusPath = Join-Path $pairDir 'workloop-runner-status.json'
  $outputPath = Join-Path $pairDir 'workloop-runner-output.md'
  $stdoutPath = Join-Path $pairDir 'workloop-runner-process.stdout.log'
  $stderrPath = Join-Path $pairDir 'workloop-runner-process.stderr.log'
  $reportPath = Join-Path $pairDir 'cc-report.md'
  $promptPath = Join-Path $pairDir 'codex-prompt.md'
  $replyPath = Join-Path $pairDir 'codex-reply.md'
  $inboxPath = Join-Path $pairDir 'cc-inbox.md'
  $status = $null
  if (Test-Path -LiteralPath $statusPath) {
    try { $status = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { $status = $null }
  }
  $statusText = if ($status -and $status.status) { [string]$status.status } else { 'unknown' }
  $message = if ($status -and $status.message) { [string]$status.message } else { '尚未写入 Workloop runner 状态。' }
  $updatedAt = if ($status -and $status.updatedAt) { [string]$status.updatedAt } else { '' }
  $processId = if ($status -and $status.processId) { [string]$status.processId } else { '' }
  $phase = if ($status -and $status.phase) { [string]$status.phase } else { 'unknown' }
  $route = if ($status -and $status.route) { [string]$status.route } else { '' }
  $nextAction = if ($status -and $status.nextAction) { [string]$status.nextAction } else { '' }
  $snapshot = if ($status -and $status.snapshot) { $status.snapshot } else { $null }
  if ($status -and $status.outputPath) { $outputPath = [string]$status.outputPath }
  if ($status -and $status.stdoutPath) { $stdoutPath = [string]$status.stdoutPath }
  if ($status -and $status.stderrPath) { $stderrPath = [string]$status.stderrPath }
  if ($status -and $status.reportPath) { $reportPath = [string]$status.reportPath }
  if ($status -and $status.promptPath) { $promptPath = [string]$status.promptPath }
  if ($status -and $status.replyPath) { $replyPath = [string]$status.replyPath }
  if ($status -and $status.inboxPath) { $inboxPath = [string]$status.inboxPath }

  $processAlive = $false
  if ($processId -match '^\d+$') {
    $processAlive = [bool](Get-Process -Id ([int]$processId) -ErrorAction SilentlyContinue)
  }
  if ($statusText -in @('queued','started','running') -and $processId -and -not $processAlive) {
    $statusText = 'stale'
    $message = "$message`n`n检测到 Workloop runner 进程已经不存在，但状态仍是 running。请查看输出、stderr、cc-report.md 和 codex-reply.md 判断是否已完成。"
  }

  function Read-StatusSnippet {
    param([string]$Path, [int]$Limit, [string]$EmptyText)
    $text = Read-AiRelayTextFile $Path
    if ($text.Length -gt $Limit) { $text = $text.Substring($text.Length - $Limit) }
    if ([string]::IsNullOrWhiteSpace($text)) { return $EmptyText }
    return $text
  }
  $output = Read-StatusSnippet -Path $outputPath -Limit 12000 -EmptyText '暂无 Workloop runner 输出。'
  $stdout = Read-StatusSnippet -Path $stdoutPath -Limit 8000 -EmptyText 'stdout 为空。'
  $stderr = Read-StatusSnippet -Path $stderrPath -Limit 8000 -EmptyText 'stderr 为空。'
  $report = Read-StatusSnippet -Path $reportPath -Limit 8000 -EmptyText 'cc-report.md 暂无内容。'
  $prompt = Read-StatusSnippet -Path $promptPath -Limit 8000 -EmptyText 'codex-prompt.md 暂无内容。'
  $reply = Read-StatusSnippet -Path $replyPath -Limit 8000 -EmptyText 'codex-reply.md 暂无内容。'
  $inbox = Read-StatusSnippet -Path $inboxPath -Limit 8000 -EmptyText 'cc-inbox.md 暂无内容。'
  if ($statusText -in @('queued','started','running','stale','unknown') -and (($stdout -match 'AI_WORKLOOP_RUNNER_STATUS=COMPLETED') -or ($output -match 'AI_WORKLOOP_RUNNER_STATUS=COMPLETED'))) {
    $statusText = 'completed'
    $message = 'Workloop runner 已完成；状态文件未能最终回写，已按 stdout/output 兜底识别为完成。'
    if ($status) {
      try {
        $status.status = 'completed'
        $status.message = $message
        $status.updatedAt = (Get-Date).ToString('o')
        Write-AiRelayJson $status $statusPath
      } catch {
      }
    }
  }
  if ($statusText -in @('queued','started','running','stale','unknown') -and (($stdout -match 'AI_WORKLOOP_RUNNER_STATUS=FAILED') -or ($output -match 'AI_WORKLOOP_RUNNER_STATUS=FAILED'))) {
    $statusText = 'failed'
    $message = 'Workloop runner 已失败；状态文件未能最终回写，已按 stdout/output 兜底识别为失败。'
  }
  if ($phase -eq 'unknown' -or [string]::IsNullOrWhiteSpace($nextAction)) {
    if ($report -ne 'cc-report.md 暂无内容。' -and (($reply -eq 'codex-reply.md 暂无内容。') -or ((Test-Path -LiteralPath $reportPath) -and (Test-Path -LiteralPath $replyPath) -and (Get-Item -LiteralPath $reportPath).LastWriteTime -gt (Get-Item -LiteralPath $replyPath).LastWriteTime))) {
      $phase = 'codex_review'
      $route = 'cc-report.md -> Codex'
      $nextAction = '把 CC 报告送给绑定的 Codex session 裁决。'
    } elseif ($reply -ne 'codex-reply.md 暂无内容。') {
      $phase = 'cc_followup'
      $route = 'codex-reply.md -> Claude Code'
      $nextAction = '让 Claude Code 读取并执行 Codex 裁决。'
    } elseif ($inbox -ne 'cc-inbox.md 暂无内容。') {
      $phase = 'cc_execute'
      $route = 'cc-inbox.md -> Claude Code'
      $nextAction = '让 Claude Code 拉取并执行未读任务。'
    } else {
      $phase = 'idle'
      $route = 'idle'
      $nextAction = '当前没有待处理消息。'
    }
  }
  $workloopInsight = Get-AiRelayStatusInsight -Kind 'workloop' -Status $statusText -ProcessAlive $processAlive -Message $message -HasOutput (-not [string]::IsNullOrWhiteSpace($output) -and $output -ne '暂无 Workloop runner 输出。') -HasStderr (-not [string]::IsNullOrWhiteSpace($stderr) -and $stderr -ne 'stderr 为空。') -HasReport ($report -ne 'cc-report.md 暂无内容。') -HasReply ($reply -ne 'codex-reply.md 暂无内容。') -HasInbox ($inbox -ne 'cc-inbox.md 暂无内容。')
  if (-not [string]::IsNullOrWhiteSpace($nextAction)) {
    $workloopInsight.NextAction = $nextAction
  }
  $workloopInsightHtml = New-StatusInsightPanelHtml -Insight $workloopInsight

  $phaseLabels = @{
    starting = '启动中'
    idle = '空闲'
    codex_review = '送 Codex 裁决'
    cc_followup = '等待 CC 执行裁决'
    cc_execute = '等待 CC 执行任务'
    completed = '目标完成'
    needs_user = '需要人工判断'
    unknown = '未知'
  }
  $phaseLabel = if ($phaseLabels.ContainsKey($phase)) { $phaseLabels[$phase] } else { $phase }
  $reportState = if ($snapshot -and $snapshot.reportReady) { '报告待送审' } elseif ($snapshot -and $snapshot.files -and $snapshot.files.report -and $snapshot.files.report.hasText) { '报告已存在' } else { '无报告' }
  $replyState = if ($snapshot -and $snapshot.replyUnread) { '裁决未读' } elseif ($snapshot -and $snapshot.files -and $snapshot.files.reply -and $snapshot.files.reply.hasText) { '裁决已存在' } else { '无裁决' }
  $inboxState = if ($snapshot -and $snapshot.inboxUnread) { '任务未读' } elseif ($snapshot -and $snapshot.files -and $snapshot.files.inbox -and $snapshot.files.inbox.hasText) { '任务已存在' } else { '无任务' }
  $goalState = if ($snapshot -and $snapshot.goalStatus) {
    $roundText = ''
    if ($snapshot.goalRound -ne $null -and $snapshot.goalMaxRounds -ne $null -and [string]$snapshot.goalMaxRounds -ne '') {
      $roundText = " $($snapshot.goalRound)/$($snapshot.goalMaxRounds)"
    }
    "$($snapshot.goalStatus)$roundText"
  } else {
    '无 goal'
  }
  function New-StageItemHtml {
    param([string]$Title, [string]$Detail, [string]$State)
    "<li class=""stage-item $State""><strong>$(Encode-Html $Title)</strong><span>$(Encode-Html $Detail)</span></li>"
  }
  $stageCheckState = if ($phase -eq 'starting') { 'current' } else { 'done' }
  $stageCodexState = if ($phase -eq 'codex_review') { 'current' } elseif ($phase -in @('cc_followup','cc_execute','completed','needs_user','idle')) { 'done' } else { 'pending' }
  $stageCcState = if ($phase -in @('cc_followup','cc_execute')) { 'current' } elseif ($phase -in @('completed','needs_user','idle')) { 'done' } else { 'pending' }
  $stageDoneState = if ($phase -in @('completed','needs_user','idle')) { 'current' } else { 'pending' }
  $stageHtml = @(
    (New-StageItemHtml -Title '1. 检查 Pair 状态' -Detail "报告：$reportState；裁决：$replyState；任务：$inboxState；Goal：$goalState" -State $stageCheckState),
    (New-StageItemHtml -Title '2. Codex 裁决' -Detail '如果 cc-report.md 比 codex-reply.md 新，就调用绑定的 Codex session 审核。' -State $stageCodexState),
    (New-StageItemHtml -Title '3. Claude Code 执行' -Detail '如果有未读裁决或任务，就交给 Claude Code 执行下一步。' -State $stageCcState),
    (New-StageItemHtml -Title '4. 收口' -Detail '完成、空闲、达到最大轮次或需要人工判断。' -State $stageDoneState)
  ) -join "`n"

  $projectArg = [System.Uri]::EscapeDataString($Project)
  $pairArg = [System.Uri]::EscapeDataString($Pair)
  $refreshUrl = "$($BaseUrl.TrimEnd('/'))/status/workloop?projectRoot=$projectArg&pair=$pairArg"
  $runUrl = "$($BaseUrl.TrimEnd('/'))/action/workloop?projectRoot=$projectArg&pair=$pairArg"
  $stopUrl = "$($BaseUrl.TrimEnd('/'))/action/workloop-stop?projectRoot=$projectArg&pair=$pairArg"
  $refresh = if ($statusText -in @('queued','started','running','unknown')) {
    "<meta http-equiv='refresh' content='2;url=$(Encode-Html $refreshUrl)'>"
  } else {
    ''
  }
  $stopForm = if ($statusText -in @('queued','started','running') -and $processAlive) {
    @"
    <form method="post" action="$(Encode-Html $stopUrl)" onsubmit="return confirm('确认停止这个 Workloop runner 进程？');">
      <button type="submit">停止 Workloop</button>
    </form>
"@
  } else {
    ''
  }
  $runForm = if (-not ($statusText -in @('queued','started','running') -and $processAlive)) {
    @"
    <form method="post" action="$(Encode-Html $runUrl)" onsubmit="return confirm('确认重新执行 /workloop？可能调用 Codex 或 Claude Code。');">
      <button class="secondary" type="submit">重新执行 /workloop</button>
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
  <title>Workloop 执行状态</title>
  <style>
    body { font-family:"Segoe UI",system-ui,sans-serif; margin:24px; color:#1f2933; background:#f7f7f4; }
    main { max-width:1120px; margin:0 auto; background:#fff; border:1px solid #d8ddd8; border-radius:8px; padding:18px; }
    h1 { margin-top:0; font-size:22px; }
    h2 { margin-top:24px; font-size:18px; }
    .badge { display:inline-block; border:1px solid #d8ddd8; border-radius:999px; padding:4px 10px; background:#f5f6f2; }
    .insight { border:1px solid #d8ddd8; border-left-width:5px; border-radius:8px; padding:12px 14px; margin:14px 0; background:#fbfcfa; }
    .insight h2 { margin:0 0 8px; font-size:16px; }
    .insight strong { display:block; margin-bottom:6px; }
    .insight p { margin:5px 0; }
    .insight-running { border-left-color:#176b5d; }
    .insight-warn { border-left-color:#d08a2f; background:#fffaf0; }
    .insight-bad { border-left-color:#b76a6a; background:#fff4f4; }
    .insight-good { border-left-color:#7ca88f; background:#f2fbf5; }
    .phase-card { border:1px solid #d8ddd8; background:#fbfcfa; border-radius:8px; padding:14px; margin:14px 0; }
    .phase-card strong { display:block; font-size:18px; margin-bottom:6px; }
    .phase-card p { margin:6px 0 0; color:#46525f; }
    .stage-list { list-style:none; margin:16px 0; padding:0; display:grid; gap:8px; }
    .stage-item { border:1px solid #d8ddd8; border-left-width:5px; border-radius:8px; padding:10px 12px; background:#fff; }
    .stage-item strong { display:block; margin-bottom:4px; }
    .stage-item span { color:#65717d; }
    .stage-item.done { border-left-color:#7ca88f; }
    .stage-item.current { border-left-color:#d08a2f; background:#fffaf0; }
    .stage-item.pending { border-left-color:#c9d0c9; color:#65717d; }
    dl { display:grid; grid-template-columns:170px 1fr; gap:8px 12px; }
    dt { color:#65717d; }
    dd { margin:0; overflow-wrap:anywhere; }
    pre { white-space:pre-wrap; overflow-wrap:anywhere; background:#f5f6f2; border:1px solid #e4e6df; border-radius:6px; padding:12px; max-height:460px; overflow:auto; }
    button { appearance:none; border:1px solid #b76a6a; border-radius:6px; background:#fff4f4; color:#8a2f2f; padding:8px 12px; font:inherit; cursor:pointer; margin-right:8px; }
    button.secondary { border-color:#8a927f; background:#f5f6f2; color:#25301f; }
    a { color:#176b5d; }
  </style>
</head>
<body>
  <main>
    <h1>Workloop 执行状态 <span class="badge">$(Encode-Html $statusText)</span></h1>
    <dl>
      <dt>Pair</dt><dd>$(Encode-Html $Pair)</dd>
      <dt>项目</dt><dd>$(Encode-Html $Project)</dd>
      <dt>状态说明</dt><dd>$(Encode-Html $message)</dd>
      <dt>当前阶段</dt><dd>$(Encode-Html $phaseLabel)</dd>
      <dt>路由</dt><dd>$(Encode-Html $route)</dd>
      <dt>下一步</dt><dd>$(Encode-Html $nextAction)</dd>
      <dt>更新时间</dt><dd>$(Encode-Html $updatedAt)</dd>
      <dt>进程 ID</dt><dd>$(Encode-Html $processId)</dd>
      <dt>runner 输出</dt><dd>$(Encode-Html $outputPath)</dd>
      <dt>stdout</dt><dd>$(Encode-Html $stdoutPath)</dd>
      <dt>stderr</dt><dd>$(Encode-Html $stderrPath)</dd>
    </dl>
    $workloopInsightHtml
    <section class="phase-card">
      <strong>当前判断：$(Encode-Html $phaseLabel)</strong>
      <p>$(Encode-Html $nextAction)</p>
      <p>路由：$(Encode-Html $route)</p>
    </section>
    <ol class="stage-list">
      $stageHtml
    </ol>
    $stopForm
    $runForm
    <h2>Workloop runner 输出</h2>
    <pre>$(Encode-Html $output)</pre>
    <h2>stdout</h2>
    <pre>$(Encode-Html $stdout)</pre>
    <h2>stderr</h2>
    <pre>$(Encode-Html $stderr)</pre>
    <h2>CC 报告 cc-report.md</h2>
    <pre>$(Encode-Html $report)</pre>
    <h2>Codex Prompt codex-prompt.md</h2>
    <pre>$(Encode-Html $prompt)</pre>
    <h2>Codex 裁决 codex-reply.md</h2>
    <pre>$(Encode-Html $reply)</pre>
    <h2>写给 CC 的下一步 cc-inbox.md</h2>
    <pre>$(Encode-Html $inbox)</pre>
    <p><a href="$(Encode-Html $refreshUrl)">手动刷新</a> · <a href="/">返回 Dashboard</a></p>
  </main>
</body>
</html>
"@
}

function New-SummaryRunnerStatusHtml {
  param(
    [string]$Project,
    [string]$Pair,
    [string]$BaseUrl
  )
  $expectedSummaryArtifactVersion = 'summary-html-artifact-v12'
  $pairDir = Get-AiRelayPairDir $Project $Pair
  $statusPath = Join-Path $pairDir 'summary-runner-status.json'
  $outputPath = Join-Path $pairDir 'summary-runner-output.md'
  $stdoutPath = Join-Path $pairDir 'summary-runner-process.stdout.log'
  $stderrPath = Join-Path $pairDir 'summary-runner-process.stderr.log'
  $summaryMdPath = Join-Path (Join-Path (Join-Path $pairDir 'summary') 'cc') 'workloop-summary-latest.md'
  $summaryHtmlPath = Join-Path (Join-Path (Join-Path $pairDir 'summary') 'cc') 'workloop-summary-latest.html'
  $analyzer = 'cc'
  $status = $null
  if (Test-Path -LiteralPath $statusPath) {
    try { $status = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { $status = $null }
  }
  $statusText = if ($status -and $status.status) { [string]$status.status } else { 'unknown' }
  $message = if ($status -and $status.message) { [string]$status.message } else { '尚未写入总结 runner 状态。' }
  $updatedAt = if ($status -and $status.updatedAt) { [string]$status.updatedAt } else { '' }
  $processId = if ($status -and $status.processId) { [string]$status.processId } else { '' }
  if ($status -and $status.analyzer) { $analyzer = [string]$status.analyzer }
  if ($status -and $status.outputPath) { $outputPath = [string]$status.outputPath }
  if ($status -and $status.stdoutPath) { $stdoutPath = [string]$status.stdoutPath }
  if ($status -and $status.stderrPath) { $stderrPath = [string]$status.stderrPath }
  if ($status -and $status.summaryMdPath) { $summaryMdPath = [string]$status.summaryMdPath }
  if ($status -and $status.summaryHtmlPath) { $summaryHtmlPath = [string]$status.summaryHtmlPath }

  $processAlive = $false
  if ($processId -match '^\d+$') {
    $processAlive = [bool](Get-Process -Id ([int]$processId) -ErrorAction SilentlyContinue)
  }
  if ($statusText -in @('queued','started','running') -and $processId -and -not $processAlive) {
    $statusText = 'stale'
    $message = "$message`n`n检测到总结 runner 进程已经不存在，但状态仍是 running。请查看输出、stdout、stderr 和 summary 文件。"
  }
  function Read-SummarySnippet {
    param([string]$Path, [int]$Limit, [string]$EmptyText)
    $text = Read-AiRelayTextFile $Path
    if ($text.Length -gt $Limit) { $text = $text.Substring($text.Length - $Limit) }
    if ([string]::IsNullOrWhiteSpace($text)) { return $EmptyText }
    return $text
  }
  $output = Read-SummarySnippet -Path $outputPath -Limit 12000 -EmptyText '暂无 summary runner 输出。'
  $stdout = Read-SummarySnippet -Path $stdoutPath -Limit 8000 -EmptyText 'stdout 为空。'
  $stderr = Read-SummarySnippet -Path $stderrPath -Limit 8000 -EmptyText 'stderr 为空。'
  $summary = Read-SummarySnippet -Path $summaryMdPath -Limit 12000 -EmptyText 'summary markdown 暂无内容。'
  $summaryFileExists = Test-Path -LiteralPath $summaryMdPath
  $summaryHtmlExists = Test-Path -LiteralPath $summaryHtmlPath
  $summaryMetaPath = Join-Path (Split-Path -Parent $summaryMdPath) 'workloop-summary-meta.json'
  $summaryStatePath = Join-Path (Split-Path -Parent $summaryMdPath) 'workloop-summary-state-latest.json'
  $summaryMeta = $null
  if (Test-Path -LiteralPath $summaryMetaPath) {
    try { $summaryMeta = Get-Content -LiteralPath $summaryMetaPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { $summaryMeta = $null }
  }
  $summaryStateDoc = $null
  if (Test-Path -LiteralPath $summaryStatePath) {
    try { $summaryStateDoc = Get-Content -LiteralPath $summaryStatePath -Raw -Encoding utf8 | ConvertFrom-Json } catch { $summaryStateDoc = $null }
  }
  $summaryState = if ($summaryStateDoc -and $summaryStateDoc.summaryState) { $summaryStateDoc.summaryState } elseif ($summaryMeta -and $summaryMeta.summaryState) { $summaryMeta.summaryState } else { $null }
  $summaryArtifactVersion = if ($summaryMeta -and $summaryMeta.artifactVersion) { [string]$summaryMeta.artifactVersion } else { '' }
  $summaryGeneratedAt = if ($summaryMeta -and $summaryMeta.generatedAt) { [string]$summaryMeta.generatedAt } else { '' }
  $summaryDiagnosis = if ($summaryState -and $summaryState.diagnosis) { [string]$summaryState.diagnosis } else { '' }
  $summaryOverall = if ($summaryState -and $summaryState.overall) { [string]$summaryState.overall } else { '' }
  $summaryEfficiency = if ($summaryState -and $summaryState.efficiency) { [string]$summaryState.efficiency } else { '' }
  $summaryNeedsUser = if ($summaryState) { [string]([bool]$summaryState.needsUser) } else { '' }
  $summaryArtifactCurrent = $summaryHtmlExists -and ($summaryArtifactVersion -eq $expectedSummaryArtifactVersion)
  $summaryArtifactOld = $summaryHtmlExists -and -not $summaryArtifactCurrent
  if ($statusText -in @('queued','started','running','stale','unknown') -and (($stdout -match 'AI_WORKLOOP_SUMMARY_RUNNER_STATUS=COMPLETED') -or ($output -match 'AI_WORKLOOP_SUMMARY_RUNNER_STATUS=COMPLETED'))) {
    $statusText = 'completed'
    $message = '总结 runner 已完成；状态文件未能最终回写，已按 stdout/output 兜底识别为完成。'
    if ($status) {
      try {
        $status.status = 'completed'
        $status.message = $message
        $status.updatedAt = (Get-Date).ToString('o')
        Write-AiRelayJson $status $statusPath
      } catch {
      }
    }
  }
  $combinedOutput = "$output`n$stdout"
  $resultStatus = 'unknown'
  $resultLabel = '结果未知'
  $resultDetail = '还没有足够信息判断总结结果。'
  $nextStep = '等待 runner 输出，或手动刷新。'
  $summaryDisplay = if ($summaryFileExists) { $summary } else { '当前没有可用的最新总结。' }
  if ($statusText -in @('queued','started','running')) {
    $resultStatus = 'running'
    $resultLabel = '生成中'
    $resultDetail = '总结 runner 正在检查缓存、调用分析器或生成总结。'
    $nextStep = '等待状态页自动刷新。'
  } elseif ($statusText -eq 'failed') {
    $resultStatus = 'failed'
    $resultLabel = '生成失败'
    $resultDetail = 'runner 执行失败，请查看 stderr 和 runner 输出。'
    $nextStep = '修复错误后重新生成总结。'
  } elseif ($combinedOutput -match 'Pair summary cache miss\.') {
    if ($summaryArtifactOld) {
      $resultStatus = 'stale_artifact'
      $resultLabel = '旧版总结'
      $resultDetail = '检测到已有总结 HTML，但它不是当前的新版中文复盘页面模板；runner 正常结束，没有覆盖旧文件。'
      $nextStep = '可以先打开旧版 HTML 查看；建议点击“重新生成总结（CC）”生成新版 HTML artifact。'
      if (-not $summaryFileExists) {
        $summaryDisplay = "检测到旧版 HTML：$summaryHtmlPath`n`n没有找到对应 Markdown。"
      }
    } elseif ($summaryHtmlExists -or $summaryFileExists) {
      $resultStatus = 'stale_summary'
      $resultLabel = '已有总结已过期'
      $resultDetail = '检测到已有总结，但它不匹配当前 pair 数据；runner 这次只是检查缓存，没有覆盖旧总结。'
      $nextStep = '可以先打开过期总结参考；建议点击“重新生成总结（CC）”生成当前版本。'
    } else {
      $resultStatus = 'cache_miss'
      $resultLabel = '缓存未命中'
      $resultDetail = '这次只是检查缓存：没有可用的最新总结，或 pair 数据已经变化；runner 正常结束，但没有生成新总结。'
      $nextStep = '点击“重新生成总结（CC）”或“重新生成总结（Codex）”。'
      $summaryDisplay = "当前没有可用的最新总结。`n`n原因：缓存检查已完成，但没有生成新总结。`n下一步：$nextStep"
    }
  } elseif ($combinedOutput -match 'Pair summary cache hit\.') {
    $resultStatus = 'cache_hit'
    $resultLabel = '缓存命中'
    $resultDetail = '已有总结与当前 pair 数据匹配，可以直接查看。'
    $nextStep = '打开总结 HTML，或返回 Dashboard。'
  } elseif ($combinedOutput -match 'Pair summary generated:') {
    $resultStatus = 'generated'
    $resultLabel = '已生成'
    $resultDetail = '本次已经重新生成总结。'
    $nextStep = '打开总结 HTML，或返回 Dashboard。'
  } elseif ($summaryFileExists -and ($statusText -eq 'completed') -and $summaryArtifactOld) {
    $resultStatus = 'stale_artifact'
    $resultLabel = '旧版总结'
    $resultDetail = '检测到已有总结文件，但它不是当前的新版 HTML artifact。'
    $nextStep = '可以先打开旧版 HTML；建议重新生成总结。'
  } elseif ($summaryFileExists -and ($statusText -eq 'completed')) {
    $resultStatus = 'available'
    $resultLabel = '已有总结'
    $resultDetail = '检测到总结文件存在，但 runner 输出没有明确标记缓存命中或重新生成。'
    $nextStep = '打开总结 HTML；如果内容不对，重新生成总结。'
  } elseif ($statusText -eq 'completed') {
    $resultStatus = 'no_summary'
    $resultLabel = '没有总结'
    $resultDetail = 'runner 已结束，但没有检测到可用总结文件。'
    $nextStep = '重新生成总结。'
    $summaryDisplay = '当前没有可用总结。'
  }
  $summaryInsight = Get-AiRelayStatusInsight -Kind 'summary' -Status $statusText -ProcessAlive $processAlive -Message $message -ResultStatus $resultStatus -HasOutput (-not [string]::IsNullOrWhiteSpace($output) -and $output -ne '暂无 summary runner 输出。') -HasStderr (-not [string]::IsNullOrWhiteSpace($stderr) -and $stderr -ne 'stderr 为空。')
  $summaryInsight.Detail = $resultDetail
  $summaryInsight.NextAction = $nextStep
  $summaryInsightHtml = New-StatusInsightPanelHtml -Insight $summaryInsight

  $projectArg = [System.Uri]::EscapeDataString($Project)
  $pairArg = [System.Uri]::EscapeDataString($Pair)
  $refreshUrl = "$($BaseUrl.TrimEnd('/'))/status/summary?projectRoot=$projectArg&pair=$pairArg"
  $regenCcUrl = "$($BaseUrl.TrimEnd('/'))/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=cc&force=1"
  $regenCodexUrl = "$($BaseUrl.TrimEnd('/'))/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=codex&force=1"
  $regenLocalUrl = "$($BaseUrl.TrimEnd('/'))/action/summary?projectRoot=$projectArg&pair=$pairArg&analyzer=local&force=1"
  $openHtmlUrl = "$($BaseUrl.TrimEnd('/'))/action/open?path=$([System.Uri]::EscapeDataString($summaryHtmlPath))"
  $openHtmlLink = if ($summaryHtmlExists) {
    $htmlLabel = if ($resultStatus -eq 'stale_summary') { '打开过期总结 HTML' } elseif ($summaryArtifactCurrent) { '打开新版总结 HTML' } elseif ($summaryArtifactOld) { '打开旧版总结 HTML' } else { '打开总结 HTML' }
    "<a href=""$(Encode-Html $openHtmlUrl)"">$(Encode-Html $htmlLabel)</a> · "
  } else {
    '<span class="muted">HTML 尚不可用</span> · '
  }
  $primaryTitle = switch ($resultStatus) {
    'running' { '总结正在生成' }
    'generated' { '总结已生成' }
    'cache_hit' { '总结可直接查看' }
    'available' { '已有总结可查看' }
    'stale_summary' { '总结已过期' }
    'stale_artifact' { '总结模板过旧' }
    'cache_miss' { '还没有可用总结' }
    'failed' { '总结生成失败' }
    default { $resultLabel }
  }
  $primaryConclusion = if ($summaryOverall) { $summaryOverall } elseif ($summaryFileExists) { '已有 Markdown 总结，可先查看内容。' } else { $resultDetail }
  $primaryAction = if ($statusText -in @('queued','started','running')) {
    '等待页面自动刷新；如果长时间不变，再查看调试输出。'
  } elseif ($summaryHtmlExists -and $resultStatus -notin @('cache_miss','failed','no_summary')) {
    '优先打开总结 HTML 查看结论；如果内容过期，再重新生成。'
  } elseif ($resultStatus -eq 'failed') {
    '查看调试输出中的 stderr，修复后重新生成。'
  } else {
    $nextStep
  }
  $primaryActionHtml = [System.Text.StringBuilder]::new()
  [void]$primaryActionHtml.AppendLine('<div class="primary-actions">')
  if ($summaryHtmlExists) {
    [void]$primaryActionHtml.AppendLine("<a class=""primary-link"" href=""$(Encode-Html $openHtmlUrl)"">打开总结 HTML</a>")
  }
  [void]$primaryActionHtml.AppendLine("<a class=""secondary-link"" href=""$(Encode-Html $refreshUrl)"">刷新状态</a>")
  [void]$primaryActionHtml.AppendLine("<a class=""secondary-link"" href=""/"">返回 Dashboard</a>")
  [void]$primaryActionHtml.AppendLine('</div>')
  $refresh = if ($statusText -in @('queued','started','running','unknown')) {
    "<meta http-equiv='refresh' content='2;url=$(Encode-Html $refreshUrl)'>"
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
  <title>Pair 总结状态</title>
  <style>
    body { font-family:"Segoe UI",system-ui,sans-serif; margin:24px; color:#1f2933; background:#f7f7f4; }
    main { max-width:1120px; margin:0 auto; background:#fff; border:1px solid #d8ddd8; border-radius:8px; padding:18px; }
    h1 { margin-top:0; font-size:22px; }
    h2 { margin-top:24px; font-size:18px; }
    .badge { display:inline-block; border:1px solid #d8ddd8; border-radius:999px; padding:4px 10px; background:#f5f6f2; }
    .insight { border:1px solid #d8ddd8; border-left-width:5px; border-radius:8px; padding:12px 14px; margin:14px 0; background:#fbfcfa; }
    .insight h2 { margin:0 0 8px; font-size:16px; }
    .insight strong { display:block; margin-bottom:6px; }
    .insight p { margin:5px 0; }
    .insight-running { border-left-color:#176b5d; }
    .insight-warn { border-left-color:#d08a2f; background:#fffaf0; }
    .insight-bad { border-left-color:#b76a6a; background:#fff4f4; }
    .insight-good { border-left-color:#7ca88f; background:#f2fbf5; }
    .badge.result-cache_miss, .badge.result-no_summary, .badge.result-stale_artifact, .badge.result-stale_summary { border-color:#d08a2f; background:#fff6e7; color:#7a4a00; }
    .badge.result-generated, .badge.result-cache_hit, .badge.result-available { border-color:#7ca88f; background:#edf8f1; color:#176b5d; }
    .badge.result-failed { border-color:#b76a6a; background:#fff4f4; color:#8a2f2f; }
    .badge.result-running { border-color:#7b8fb3; background:#eef4ff; color:#274c7a; }
    .hero { border:1px solid #d8ddd8; border-left:6px solid #176b5d; border-radius:10px; padding:16px 18px; margin:14px 0 16px; background:#fbfcfa; }
    .hero h2 { margin:0 0 10px; font-size:22px; }
    .hero-grid { display:grid; grid-template-columns:150px minmax(0,1fr); gap:8px 14px; margin:0; }
    .hero-grid dt { color:#65717d; }
    .hero-grid dd { margin:0; overflow-wrap:anywhere; }
    .primary-actions { display:flex; flex-wrap:wrap; gap:8px; margin-top:14px; }
    .primary-link, .secondary-link { display:inline-block; border:1px solid #176b5d; border-radius:6px; padding:8px 12px; text-decoration:none; }
    .primary-link { background:#176b5d; color:#fff; }
    .secondary-link { background:#e7f2ed; color:#176b5d; }
    .debug-meta { margin:14px 0; }
    .debug-meta summary { cursor:pointer; color:#65717d; }
    dl { display:grid; grid-template-columns:170px 1fr; gap:8px 12px; }
    dt { color:#65717d; }
    dd { margin:0; overflow-wrap:anywhere; }
    pre { white-space:pre-wrap; overflow-wrap:anywhere; background:#f5f6f2; border:1px solid #e4e6df; border-radius:6px; padding:12px; max-height:460px; overflow:auto; }
    a { color:#176b5d; }
    .muted { color:#65717d; }
    .inline-actions { display:flex; flex-wrap:wrap; gap:8px; margin:14px 0; }
    .inline-actions form { margin:0; }
    button { border:1px solid #176b5d; border-radius:6px; background:#e7f2ed; color:#176b5d; padding:8px 12px; font:inherit; cursor:pointer; }
    button.warn { border-color:#d08a2f; background:#fff6e7; color:#7a4a00; }
  </style>
</head>
<body>
  <main>
    <h1>Pair 总结 <span class="badge">Runner: $(Encode-Html $statusText)</span> <span class="badge result-$(Encode-Html $resultStatus)">结果: $(Encode-Html $resultLabel)</span></h1>
    <section class="hero">
      <h2>$(Encode-Html $primaryTitle)</h2>
      <dl class="hero-grid">
        <dt>当前结论</dt><dd>$(Encode-Html $primaryConclusion)</dd>
        <dt>你现在要做</dt><dd>$(Encode-Html $primaryAction)</dd>
        <dt>分析方式</dt><dd>$(Encode-Html $analyzer)</dd>
        <dt>Pair</dt><dd>$(Encode-Html $Pair)</dd>
      </dl>
      $($primaryActionHtml.ToString())
    </section>
    $summaryInsightHtml
    <section class="inline-actions" aria-label="重新生成总结">
      <form method="post" action="$(Encode-Html $regenCcUrl)"><button class="warn" type="submit">重新生成新版总结（CC）</button></form>
      <form method="post" action="$(Encode-Html $regenCodexUrl)"><button class="warn" type="submit">重新生成新版总结（Codex）</button></form>
      <form method="post" action="$(Encode-Html $regenLocalUrl)"><button type="submit">重新生成本地摘要</button></form>
    </section>
    <h2>总结内容</h2>
    <pre>$(Encode-Html $summaryDisplay)</pre>
    <details class="debug-meta">
      <summary>技术信息 / 文件路径</summary>
      <dl>
      <dt>Pair</dt><dd>$(Encode-Html $Pair)</dd>
      <dt>项目</dt><dd>$(Encode-Html $Project)</dd>
      <dt>分析方式</dt><dd>$(Encode-Html $analyzer)</dd>
      <dt>Runner 说明</dt><dd>$(Encode-Html $message)</dd>
      <dt>总结结果</dt><dd>$(Encode-Html $resultDetail)</dd>
      <dt>下一步</dt><dd>$(Encode-Html $nextStep)</dd>
      <dt>更新时间</dt><dd>$(Encode-Html $updatedAt)</dd>
      <dt>进程 ID</dt><dd>$(Encode-Html $processId)</dd>
      <dt>Markdown</dt><dd>$(Encode-Html $summaryMdPath)</dd>
      <dt>HTML</dt><dd>$(Encode-Html $summaryHtmlPath)</dd>
      <dt>状态 JSON</dt><dd>$(Encode-Html $summaryStatePath)</dd>
      <dt>Artifact</dt><dd>$(Encode-Html $(if ($summaryArtifactVersion) { $summaryArtifactVersion } else { '未记录，通常表示旧版总结' }))</dd>
      <dt>生成时间</dt><dd>$(Encode-Html $summaryGeneratedAt)</dd>
      <dt>诊断</dt><dd>$(Encode-Html $(if ($summaryDiagnosis) { $summaryDiagnosis } else { '未生成' }))</dd>
      <dt>结构化结论</dt><dd>$(Encode-Html $(if ($summaryOverall) { $summaryOverall } else { '未生成' }))</dd>
      <dt>执行效率</dt><dd>$(Encode-Html $(if ($summaryEfficiency) { $summaryEfficiency } else { '未生成' }))</dd>
      <dt>需要介入</dt><dd>$(Encode-Html $(if ($summaryNeedsUser) { $summaryNeedsUser } else { '未生成' }))</dd>
      </dl>
    </details>
    <details class="debug-meta">
      <summary>调试输出：summary runner / stdout / stderr</summary>
      <h2>summary runner 输出</h2>
      <pre>$(Encode-Html $output)</pre>
      <h2>stdout</h2>
      <pre>$(Encode-Html $stdout)</pre>
      <h2>stderr</h2>
      <pre>$(Encode-Html $stderr)</pre>
    </details>
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

function Get-WorkloopProcessRecords {
  $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^(cmd|powershell|pwsh|node|claude|codex)\.exe$'
  })
  $byPid = @{}
  foreach ($p in $all) { $byPid[[int]$p.ProcessId] = $p }
  $mcpPattern = 'claude-code-wechat-channel|chrome-devtools-mcp|context7-mcp|comfyui-mcp|zai-mcp-server|mcp-server|@modelcontextprotocol|@z_ai'
  $records = @()
  foreach ($p in $all) {
    $cmd = [string]$p.CommandLine
    $kind = if ($cmd -match 'ai-workloop-dashboard-server\.ps1|ai-workloop-dashboard\.ps1') { 'Workloop 面板' }
      elseif ($cmd -match $mcpPattern) { 'MCP 子进程' }
      elseif ($p.Name -eq 'claude.exe') { 'Claude Code' }
      elseif ($p.Name -eq 'codex.exe') { 'Codex' }
      elseif ($cmd -match 'Cursor|cursor|shellIntegration') { 'Cursor 终端' }
      elseif ($p.Name -eq 'cmd.exe' -and [string]::IsNullOrWhiteSpace($cmd)) { '未知 cmd' }
      else { '其他' }

    $ancestorKinds = @()
    $ancestorPid = [int]$p.ParentProcessId
    $guard = 0
    while ($ancestorPid -gt 0 -and $guard -lt 24) {
      $guard++
      if (-not $byPid.ContainsKey($ancestorPid)) { break }
      $ancestor = $byPid[$ancestorPid]
      $ancestorCmd = [string]$ancestor.CommandLine
      if ($ancestor.Name -eq 'claude.exe') { $ancestorKinds += 'Claude Code' }
      elseif ($ancestor.Name -eq 'codex.exe') { $ancestorKinds += 'Codex' }
      elseif ($ancestorCmd -match 'ai-workloop-dashboard-server\.ps1') { $ancestorKinds += 'Workloop 面板' }
      elseif ($ancestorCmd -match 'Cursor|cursor|shellIntegration') { $ancestorKinds += 'Cursor 终端' }
      $ancestorPid = [int]$ancestor.ParentProcessId
    }
    $root = ($ancestorKinds | Select-Object -First 1)
    if (-not $root) { $root = '未找到上游会话' }
    $cleanupCandidate = ($kind -eq 'MCP 子进程' -and $ancestorKinds -notcontains 'Claude Code' -and $ancestorKinds -notcontains 'Codex')
    $records += [pscustomobject]@{
      pid = [int]$p.ProcessId
      ppid = [int]$p.ParentProcessId
      name = [string]$p.Name
      kind = $kind
      root = $root
      cleanupCandidate = [bool]$cleanupCandidate
      createdAt = if ($p.CreationDate) { ([datetime]$p.CreationDate).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
      commandLine = $cmd
    }
  }
  $records | Sort-Object kind, createdAt, pid
}

function New-ProcessDiagnosticsHtml {
  param([string]$BaseUrl)
  $records = @(Get-WorkloopProcessRecords)
  $groups = @($records | Group-Object kind | Sort-Object Count -Descending)
  $candidateCount = @($records | Where-Object { $_.cleanupCandidate }).Count
  $summary = ($groups | ForEach-Object { "<li><strong>$($_.Count)</strong> $(Encode-Html $_.Name)</li>" }) -join "`n"
  $rows = ($records | ForEach-Object {
    $class = if ($_.cleanupCandidate) { 'candidate' } else { '' }
    $safe = if ($_.cleanupCandidate) { '可清理候选' } else { '保留' }
    "<tr class='$class'><td>$($_.pid)</td><td>$($_.ppid)</td><td>$(Encode-Html $_.name)</td><td>$(Encode-Html $_.kind)</td><td>$(Encode-Html $_.root)</td><td>$(Encode-Html $safe)</td><td>$(Encode-Html $_.createdAt)</td><td><code>$(Encode-Html $_.commandLine)</code></td></tr>"
  }) -join "`n"
  $cleanupUrl = "$($BaseUrl.TrimEnd('/'))/action/process-cleanup-orphan-mcp"
  $cleanupForm = if ($candidateCount -gt 0) {
    @"
    <form method="post" action="$(Encode-Html $cleanupUrl)" onsubmit="return confirm('只会停止未挂在 Claude/Codex 上游会话下的 MCP 子进程。确认清理？');">
      <button type="submit">清理孤儿 MCP 候选（$candidateCount）</button>
    </form>
"@
  } else {
    '<p class="muted">没有发现可清理的孤儿 MCP 候选。正在挂在 Claude/Codex 会话下的 MCP 不会自动清理。</p>'
  }
  @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>进程诊断</title>
  <style>
    body { font-family:"Segoe UI",system-ui,sans-serif; margin:24px; color:#1f2933; background:#f7f7f4; }
    main { max-width:1280px; margin:0 auto; background:#fff; border:1px solid #d8ddd8; border-radius:8px; padding:18px; }
    h1 { margin-top:0; font-size:22px; }
    ul { display:flex; flex-wrap:wrap; gap:10px 18px; padding-left:18px; }
    table { width:100%; border-collapse:collapse; font-size:12px; }
    th,td { border-top:1px solid #e4e6df; padding:7px; text-align:left; vertical-align:top; }
    th { color:#65717d; }
    code { white-space:pre-wrap; overflow-wrap:anywhere; font-family:Consolas,monospace; }
    .candidate { background:#fff8ed; }
    button { appearance:none; border:1px solid #b76a6a; border-radius:6px; background:#fff4f4; color:#8a2f2f; padding:8px 12px; font:inherit; cursor:pointer; }
    .muted { color:#65717d; }
    a { color:#176b5d; }
  </style>
</head>
<body>
  <main>
    <h1>Workloop 进程诊断</h1>
    <p class="muted">这里只做本机进程归类。默认不会清理 Claude/Codex 当前会话正在使用的 MCP 子进程。</p>
    <ul>$summary</ul>
    $cleanupForm
    <table>
      <thead><tr><th>PID</th><th>PPID</th><th>进程</th><th>来源</th><th>上游</th><th>建议</th><th>启动时间</th><th>命令行</th></tr></thead>
      <tbody>$rows</tbody>
    </table>
    <p><a href="/status/processes">刷新</a> · <a href="/">返回 Dashboard</a></p>
  </main>
</body>
</html>
"@
}

function Get-AiRelayPowerShellHost {
  $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($pwsh) { return $pwsh }
  $powershell = Get-Command powershell -ErrorAction SilentlyContinue
  if ($powershell) { return $powershell }
  throw "PowerShell host not found."
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
  $status.message = "检测到上一次 runner 状态是 $state，但进程已不存在。已标记为 stale，可重新执行。"
  $status.updatedAt = (Get-Date).ToString('o')
  Write-AiRelayJson $status $StatusPath
  return $null
}

function Start-WorkloopRunnerProcess {
  param(
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$Pair
  )
  $pairDir = Get-AiRelayPairDir $Project $Pair
  if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair 不存在：$pairDir" }
  $statusPath = Join-Path $pairDir 'workloop-runner-status.json'
  $activeStatus = Get-ActiveCcRunnerStatus -StatusPath $statusPath
  if ($activeStatus) {
    return [pscustomobject]@{
      Started = $false
      ProcessId = [string]$activeStatus.processId
      StatusPath = $statusPath
    }
  }
  $runnerScript = Join-Path $PSScriptRoot 'ai-workloop-runner.ps1'
  if (-not (Test-Path -LiteralPath $runnerScript)) { throw "Workloop runner 不存在：$runnerScript" }
  $powershell = Get-AiRelayPowerShellHost
  $runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
  $stdoutPath = Join-Path $pairDir "workloop-runner-process-$runId.stdout.log"
  $stderrPath = Join-Path $pairDir "workloop-runner-process-$runId.stderr.log"
  $outputPath = Join-Path $pairDir 'workloop-runner-output.md'
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    projectRoot = $Project
    status = 'queued'
    message = '已收到面板请求，Workloop runner 正在排队启动。'
    exitCode = 0
    updatedAt = (Get-Date).ToString('o')
    processId = ''
    outputPath = $outputPath
    stdoutPath = $stdoutPath
    stderrPath = $stderrPath
    reportPath = Join-Path $pairDir 'cc-report.md'
    promptPath = Join-Path $pairDir 'codex-prompt.md'
    replyPath = Join-Path $pairDir 'codex-reply.md'
    inboxPath = Join-Path $pairDir 'cc-inbox.md'
  }) $statusPath
  $process = Start-Process -FilePath $powershell.Source -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $runnerScript,
    '-ProjectRoot',
    $Project,
    '-Pair',
    $Pair,
    '-StdoutPath',
    $stdoutPath,
    '-StderrPath',
    $stderrPath
  ) -WorkingDirectory $Project -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    projectRoot = $Project
    status = 'started'
    message = 'Workloop runner 已启动，正在推进状态机。'
    exitCode = 0
    updatedAt = (Get-Date).ToString('o')
    processId = $process.Id
    outputPath = $outputPath
    stdoutPath = $stdoutPath
    stderrPath = $stderrPath
    reportPath = Join-Path $pairDir 'cc-report.md'
    promptPath = Join-Path $pairDir 'codex-prompt.md'
    replyPath = Join-Path $pairDir 'codex-reply.md'
    inboxPath = Join-Path $pairDir 'cc-inbox.md'
  }) $statusPath
  return [pscustomobject]@{
    Started = $true
    ProcessId = $process.Id
    StatusPath = $statusPath
  }
}

function Start-SummaryRunnerProcess {
  param(
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$Pair,
    [ValidateSet('cc','codex','local')][string]$Analyzer = 'cc',
    [switch]$UseCache,
    [switch]$CacheOnly,
    [switch]$Open
  )
  $pairDir = Get-AiRelayPairDir $Project $Pair
  if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair 不存在：$pairDir" }
  $statusPath = Join-Path $pairDir 'summary-runner-status.json'
  $activeStatus = Get-ActiveCcRunnerStatus -StatusPath $statusPath
  if ($activeStatus) {
    return [pscustomobject]@{
      Started = $false
      ProcessId = [string]$activeStatus.processId
      StatusPath = $statusPath
    }
  }
  $runnerScript = Join-Path $PSScriptRoot 'ai-workloop-summary-runner.ps1'
  if (-not (Test-Path -LiteralPath $runnerScript)) { throw "Summary runner 不存在：$runnerScript" }
  $powershell = Get-AiRelayPowerShellHost
  $runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
  $stdoutPath = Join-Path $pairDir "summary-runner-process-$runId.stdout.log"
  $stderrPath = Join-Path $pairDir "summary-runner-process-$runId.stderr.log"
  $summaryDir = Join-Path (Join-Path $pairDir 'summary') $Analyzer
  $args = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $runnerScript,
    '-ProjectRoot',
    $Project,
    '-Pair',
    $Pair,
    '-Analyzer',
    $Analyzer,
    '-StdoutPath',
    $stdoutPath,
    '-StderrPath',
    $stderrPath
  )
  if ($UseCache) { $args += '-UseCache' }
  if ($CacheOnly) { $args += '-CacheOnly' }
  if ($Open) { $args += '-Open' }
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    projectRoot = $Project
    analyzer = $Analyzer
    status = 'queued'
    message = 'Pair summary runner is queued.'
    exitCode = 0
    updatedAt = (Get-Date).ToString('o')
    processId = ''
    outputPath = Join-Path $pairDir 'summary-runner-output.md'
    stdoutPath = $stdoutPath
    stderrPath = $stderrPath
    summaryMdPath = Join-Path $summaryDir 'workloop-summary-latest.md'
    summaryHtmlPath = Join-Path $summaryDir 'workloop-summary-latest.html'
  }) $statusPath
  $process = Start-Process -FilePath $powershell.Source -ArgumentList $args -WorkingDirectory $Project -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    projectRoot = $Project
    analyzer = $Analyzer
    status = 'started'
    message = 'Pair summary runner started.'
    exitCode = 0
    updatedAt = (Get-Date).ToString('o')
    processId = $process.Id
    outputPath = Join-Path $pairDir 'summary-runner-output.md'
    stdoutPath = $stdoutPath
    stderrPath = $stderrPath
    summaryMdPath = Join-Path $summaryDir 'workloop-summary-latest.md'
    summaryHtmlPath = Join-Path $summaryDir 'workloop-summary-latest.html'
  }) $statusPath
  return [pscustomobject]@{
    Started = $true
    ProcessId = $process.Id
    StatusPath = $statusPath
  }
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
  $sessionName = "workloop-$Pair"
  $sessionId = ''
  $claudeProjectsRoot = Join-Path $workloopHome '.claude\projects'
  for ($attempt = 0; $attempt -lt 10; $attempt++) {
    $candidate = [guid]::NewGuid().ToString()
    $exists = $false
    if (Test-Path -LiteralPath $claudeProjectsRoot) {
      $existingFile = Get-ChildItem -LiteralPath $claudeProjectsRoot -Recurse -File -Filter "$candidate.jsonl" -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($existingFile) { $exists = $true }
    }
    if (-not $exists) {
      $sessionId = $candidate
      break
    }
  }
  if ([string]::IsNullOrWhiteSpace($sessionId)) {
    throw "无法生成唯一 Claude Code session id。"
  }
  $prompt = @"
Initialize Agent Workloop pair "$Pair" for this project.

Rules:
- You are the Claude Code execution thread for this pair.
- Do not modify files.
- Do not inspect files.
- Do not run tools.
- Reply exactly: Agent Workloop Claude Code session initialized.
"@
  $claudeArgs = @(
    '--print',
    '--session-id', $sessionId,
    '--name', $sessionName,
    '--tools', '',
    '--permission-mode', 'plan',
    '--output-format', 'json',
    $prompt
  )
  Push-Location $Project
  try {
    $output = & $claude.Source @claudeArgs 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  if ($exitCode -ne 0) {
    throw "创建 Claude Code session 失败。ExitCode=$exitCode`n$output"
  }
  return [pscustomobject]@{
    SessionId = $sessionId
    SessionName = $sessionName
    Output = $output
  }
}

function Set-WorkloopCcSessionId {
  param(
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$Pair,
    [AllowEmptyString()][string]$CcSessionId = '',
    [AllowEmptyString()][string]$CcSessionName = ''
  )
  if ([string]::IsNullOrWhiteSpace($CcSessionName) -and -not [string]::IsNullOrWhiteSpace($CcSessionId)) {
    $CcSessionName = "workloop-$Pair"
  }
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
      $pairJson | Add-Member -NotePropertyName ccSessionName -NotePropertyValue $CcSessionName -Force
    } else {
      $pairJson.ccSessionName = $CcSessionName
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
      ccSessionName = $CcSessionName
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
      $bindText = [regex]::Replace($bindText, '(?m)^ccSessionName:.*$', "ccSessionName: $CcSessionName")
    }
    Set-Content -LiteralPath $bindPath -Value $bindText -Encoding utf8
  }
  Add-AiRelayLog -PairDir $pairDir -Event 'bind-cc-session' -Detail "Bound Claude Code session id $CcSessionId name $CcSessionName."
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
  $powershell = Get-AiRelayPowerShellHost
  & $powershell.Source -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\ai-workloop-dashboard.ps1" @args | Out-Null
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
      $ccSessionName = ''
      if ([string]::IsNullOrWhiteSpace($ccSessionId)) {
        $ccInit = New-WorkloopClaudeSessionId -Project $project -Pair $pair
        $ccSessionId = $ccInit.SessionId
        $ccSessionName = $ccInit.SessionName
        $ccInitOutput = $ccInit.Output
      } else {
        $ccSessionName = "workloop-$pair"
      }
      $output = Invoke-Captured {
        Push-Location $project
        try {
          & "$PSScriptRoot\ai-relay-bind-cc.ps1" -Pair $pair -Task $task -CcSessionId $ccSessionId -CcSessionName $ccSessionName
        } finally { Pop-Location }
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
      $goalBootstrapped = Ensure-WorkloopGoalFromPairTask -Project $project -Pair $pair
      $bindPath = Join-Path (Get-AiRelayPairDir $project $pair) 'bind-request.md'
      $ccBindLabel = "$ccSessionName / $ccSessionId"
      $goalMessage = if ($goalBootstrapped) { '<p>已将创建时填写的目标写入 <code>goal.json</code>，可以直接点击“开始 / 继续目标”。</p>' } else { '' }
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Pair 已创建并绑定' "<p>已创建 Pair，并绑定 Codex 与 Claude Code session。</p>$goalMessage<p>Codex session id: <code>$(Encode-Html $codexSessionId)</code></p><p>Claude Code session: <code>$(Encode-Html $ccBindLabel)</code></p><pre>$(Encode-Html ($output + "`n" + $bindOutput))</pre><p>Bind request: <code>$(Encode-Html $bindPath)</code></p>")
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
      $maxRounds = 10
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
      $statusPath = Join-Path $pairDir 'codex-plan-status.json'
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
      Write-AiRelayJson ([ordered]@{
        pairId = $pair
        projectRoot = $project
        status = 'queued'
        message = 'Codex 规划 runner 已排队启动。'
        exitCode = 0
        updatedAt = (Get-Date).ToString('o')
        processId = 0
        planPromptPath = $planPromptPath
        planReplyPath = Join-Path $pairDir 'codex-plan-reply.md'
        inboxPath = $inboxPath
        logPath = Join-Path $pairDir 'codex-plan.log'
      }) $statusPath
      $powershell = Get-AiRelayPowerShellHost
      $runnerScript = Join-Path $PSScriptRoot 'ai-workloop-plan-runner.ps1'
      if (-not (Test-Path -LiteralPath $runnerScript)) { throw "规划 runner 不存在：$runnerScript" }
      Write-Host ("[{0}] PLAN task foreground project={1} pair={2} codex={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $codexSessionId)
      $process = Start-Process -FilePath $powershell.Source -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $runnerScript,
        '-ProjectRoot',
        $project,
        '-Pair',
        $pair,
        '-CodexSessionId',
        $codexSessionId,
        '-Goal',
        $goal,
        '-MaxRounds',
        [string]$maxRounds
      ) -WorkingDirectory $project -WindowStyle Normal -PassThru
      Write-AiRelayJson ([ordered]@{
        pairId = $pair
        projectRoot = $project
        status = 'started'
        message = '已打开 Codex planner 前台终端。'
        exitCode = 0
        updatedAt = (Get-Date).ToString('o')
        processId = $process.Id
        planPromptPath = $planPromptPath
        planReplyPath = Join-Path $pairDir 'codex-plan-reply.md'
        inboxPath = $inboxPath
        logPath = Join-Path $pairDir 'codex-plan.log'
      }) $statusPath
      $projectArg = [System.Uri]::EscapeDataString($project)
      $pairArg = [System.Uri]::EscapeDataString($pair)
      $statusUrl = "$($prefix.TrimEnd('/'))/status/codex-plan?projectRoot=$projectArg&pair=$pairArg"
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Codex 规划已启动' "<p>已打开 Codex planner 前台终端。规划完成后会自动写入 cc-inbox.md。</p><p>进程 ID：$(Encode-Html ([string]$process.Id))</p><p><a href='$(Encode-Html $statusUrl)'>打开 Codex 规划状态页</a></p>")
      return
    }

    if ($path -eq '/action/resume-goal') {
      $form = Get-RequestFormMap $Request
      $projectText = if ($form.ContainsKey('projectRoot') -and -not [string]::IsNullOrWhiteSpace([string]$form['projectRoot'])) { [string]$form['projectRoot'] } else { Decode-Query $query['projectRoot'] }
      $pair = if ($form.ContainsKey('pair') -and -not [string]::IsNullOrWhiteSpace([string]$form['pair'])) { [string]$form['pair'] } else { Decode-Query $query['pair'] }
      if ([string]::IsNullOrWhiteSpace($projectText)) { throw "缺少 projectRoot，无法续跑目标。" }
      if ([string]::IsNullOrWhiteSpace($pair)) { throw "缺少 pair，无法续跑目标。" }
      $project = Assert-AllowedProject $projectText
      Assert-AiRelayPairName $pair
      $goal = ([string]$form['goal']).Trim()
      if ([string]::IsNullOrWhiteSpace($goal)) { throw "请填写续跑目标。" }
      $pairDir = Get-AiRelayPairDir $project $pair
      if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair 不存在：$pairDir" }
      $pairJson = Read-AiRelayPairJson $pairDir
      if ([string]::IsNullOrWhiteSpace([string]$pairJson.codexSessionId)) {
        throw "pair.json 缺少 codexSessionId，请先绑定/重绑 Codex。"
      }
      $goalPath = Join-Path $pairDir 'goal.json'
      $oldGoal = $null
      if (Test-Path -LiteralPath $goalPath) {
        try { $oldGoal = Get-Content -LiteralPath $goalPath -Raw -Encoding utf8 | ConvertFrom-Json } catch {}
      }
      $currentRound = 0
      if ($oldGoal -and $oldGoal.round -ne $null -and [string]$oldGoal.round -match '^\d+$') { $currentRound = [int]$oldGoal.round }
      $maxRounds = $currentRound + 5
      if ([string]$form['maxRounds'] -match '^\d+$') { $maxRounds = [int]$form['maxRounds'] }
      if ($maxRounds -le $currentRound) { throw "新的总最大轮次必须大于当前轮次。当前轮次：$currentRound，输入值：$maxRounds。" }
      if ($maxRounds -gt 50) { $maxRounds = 50 }
      $now = (Get-Date).ToString('o')
      $startedAt = if ($oldGoal -and $oldGoal.startedAt) { [string]$oldGoal.startedAt } else { $now }
      Write-AiRelayJson ([ordered]@{
        pairId = $pair
        goal = $goal
        status = 'planned'
        round = $currentRound
        maxRounds = $maxRounds
        startedAt = $startedAt
        updatedAt = $now
        stopReason = ''
        lastDecision = ''
        lastNextInstruction = ''
        resumedAt = $now
        resumedFromStatus = if ($oldGoal -and $oldGoal.status) { [string]$oldGoal.status } else { '' }
        previousGoal = if ($oldGoal -and $oldGoal.goal) { [string]$oldGoal.goal } else { '' }
      }) $goalPath
      Set-Content -LiteralPath (Join-Path $pairDir 'user-goal.md') -Value @"
# User Goal - $pair

## Goal
$goal

Current round: $currentRound
Max rounds: $maxRounds
"@ -Encoding utf8

      foreach ($name in @('codex-reply','cc-inbox')) {
        $sourcePath = Join-Path $pairDir "$name.md"
        $readPath = Join-Path $pairDir "$name.read.md"
        if (Test-Path -LiteralPath $sourcePath) {
          Copy-Item -LiteralPath $sourcePath -Destination $readPath -Force
        }
      }
      Add-AiRelayLog -PairDir $pairDir -Event 'workloop-goal-resume' -Detail "Resumed same pair from round $currentRound to maxRounds=$maxRounds.`n$goal"
      $runner = Start-WorkloopRunnerProcess -Project $project -Pair $pair
      Write-Host ("[{0}] RESUME goal project={1} pair={2} round={3} max={4} runnerStarted={5}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $currentRound, $maxRounds, $runner.Started)
      Write-HttpText -Response $Response -Text (New-WorkloopRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
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
      $powershell = Get-AiRelayPowerShellHost
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

    if ($path -eq '/action/cc-terminal') {
      $project = Assert-AllowedProject (Decode-Query $query['projectRoot'])
      $pair = Decode-Query $query['pair']
      Assert-AiRelayPairName $pair
      $pairDir = Get-AiRelayPairDir $project $pair
      $pairJson = Read-AiRelayPairJson $pairDir
      $ccSessionId = [string]$pairJson.ccSessionId
      $ccSessionName = [string]$pairJson.ccSessionName
      if ([string]::IsNullOrWhiteSpace($ccSessionId)) {
        throw "pair.json 缺少 ccSessionId，请先绑定/重绑 CC。"
      }
      $powershell = Get-AiRelayPowerShellHost
      $terminalCommand = @"
`$ErrorActionPreference = 'Continue'
try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
  `$OutputEncoding = [System.Text.UTF8Encoding]::new()
  `$Host.UI.RawUI.WindowTitle = 'workloop-cc-$($pair.Replace("'", "''"))'
} catch {}
Set-Location -LiteralPath '$($project.Replace("'", "''"))'
Write-Host 'Agent Workloop Claude Code terminal'
Write-Host 'Pair: $($pair.Replace("'", "''"))'
Write-Host 'Project: $($project.Replace("'", "''"))'
Write-Host 'Claude Code session: $($ccSessionId.Replace("'", "''"))'
Write-Host 'Claude Code session name: $($ccSessionName.Replace("'", "''"))'
Write-Host ''
Write-Host '正在打开 Claude Code 原会话。这个窗口只用于恢复/查看该会话，不会自动下发 Workloop 任务。'
Write-Host ''
`$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not `$claude) {
  Write-Host 'claude CLI not found in PATH.' -ForegroundColor Red
  Read-Host '按 Enter 关闭窗口'
  exit 1
}
& `$claude.Source --resume '$($ccSessionId.Replace("'", "''"))'
Write-Host ''
Read-Host 'Claude Code 终端已退出，按 Enter 关闭窗口'
"@
      $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($terminalCommand))
      Start-Process -FilePath $powershell.Source -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        $encodedCommand
      ) -WorkingDirectory $project -WindowStyle Normal | Out-Null
      Write-HttpText -Response $Response -Text (New-ResultHtml 'CC 原会话已打开' "<p>已打开绑定的 Claude Code session。</p><pre>$(Encode-Html $ccSessionId)</pre>")
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
      $ccSessionName = ''
      if ([string]::IsNullOrWhiteSpace($ccSessionId)) {
        $ccInit = New-WorkloopClaudeSessionId -Project $project -Pair $pair
        $ccSessionId = $ccInit.SessionId
        $ccSessionName = $ccInit.SessionName
        $ccInitOutput = $ccInit.Output
      } else {
        $ccSessionName = "workloop-$pair"
      }
      if (-not [string]::IsNullOrWhiteSpace($ccSessionId) -and $ccSessionId -notmatch '^[0-9a-fA-F-]{20,}$') {
        throw "Claude Code Session ID 格式看起来不正确：$ccSessionId"
      }
      Write-Host ("[{0}] REBIND cc project={1} pair={2} session={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $ccSessionId)
      Set-WorkloopCcSessionId -Project $project -Pair $pair -CcSessionId $ccSessionId -CcSessionName $ccSessionName
      if ($ccInitOutput) {
        Set-Content -LiteralPath (Join-Path (Get-AiRelayPairDir $project $pair) 'cc-session-init.log') -Value $ccInitOutput -Encoding utf8
      }
      $ccBindLabel = "$ccSessionName / $ccSessionId"
      Write-HttpText -Response $Response -Text (New-ResultHtml 'Claude Code 绑定已更新' "<p>Pair 的 Claude Code 执行方式已更新。</p><p>Claude Code session: <code>$(Encode-Html $ccBindLabel)</code></p>")
      return
    }

    if ($path -eq '/action/process-cleanup-orphan-mcp') {
      $records = @(Get-WorkloopProcessRecords | Where-Object { $_.cleanupCandidate })
      $stopped = @()
      foreach ($record in $records) {
        if ($record.pid -eq $PID) { continue }
        try {
          Stop-ProcessTreeById -ProcessId ([int]$record.pid)
          $stopped += "PID $($record.pid) $($record.name) $($record.commandLine)"
        } catch {
          $stopped += "FAILED PID $($record.pid): $($_.Exception.Message)"
        }
      }
      Write-Host ("[{0}] PROCESS cleanup orphan mcp count={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $stopped.Count)
      $body = if ($stopped.Count -gt 0) { "<pre>$(Encode-Html ($stopped -join "`n"))</pre>" } else { '<p>没有可清理的孤儿 MCP 候选。</p>' }
      Write-HttpText -Response $Response -Text (New-ResultHtml '进程清理完成' "$body<p><a href='/status/processes'>返回进程诊断</a></p>")
      return
    }

    $project = Assert-AllowedProject (Decode-Query $query['projectRoot'])
    $pair = Decode-Query $query['pair']
    Assert-AiRelayPairName $pair

    if ($path -eq '/action/continue-goal') {
      Write-Host ("[{0}] ROUTE continue-goal project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      $pairDir = Get-AiRelayPairDir $project $pair
      if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair 不存在：$pairDir" }
      $goalPath = Join-Path $pairDir 'goal.json'
      $goalBootstrapped = Ensure-WorkloopGoalFromPairTask -Project $project -Pair $pair
      if ($goalBootstrapped) {
        Write-Host ("[{0}] BOOTSTRAP goal from pair task project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      }
      $route = Get-WorkloopRoute -PairDir $pairDir
      if (-not (Test-Path -LiteralPath $goalPath) -and $route.Action -eq 'idle') {
        Write-HttpText -Response $Response -Text (New-ResultHtml '需要先设置最终目标' '<p>当前 pair 没有可推进的最终目标，也没有待执行任务或待送审报告。请先在卡片上设置最终目标。</p><p>如果卡片顶部显示了“目标”，但仍看到此提示，请检查 pair.json.task 是否为空，或 goal.json 是否被手动删除。</p>')
        return
      }
      $runner = Start-WorkloopRunnerProcess -Project $project -Pair $pair
      if ($runner.Started) {
        Write-Host ("[{0}] continue-goal started workloop-runner pid={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $runner.ProcessId)
      } else {
        Write-Host ("[{0}] continue-goal reused active workloop-runner pid={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $runner.ProcessId)
      }
      Write-HttpText -Response $Response -Text (New-WorkloopRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
      return
    }

    if ($path -eq '/action/workloop') {
      Write-Host ("[{0}] RUN workloop project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      $goalBootstrapped = Ensure-WorkloopGoalFromPairTask -Project $project -Pair $pair
      if ($goalBootstrapped) {
        Write-Host ("[{0}] BOOTSTRAP goal from pair task project={1} pair={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair)
      }
      $runner = Start-WorkloopRunnerProcess -Project $project -Pair $pair
      if ($runner.Started) {
        Write-Host ("[{0}] workloop-runner started pid={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $runner.ProcessId)
      } else {
        Write-Host ("[{0}] SKIP workloop-runner already active project={1} pair={2} pid={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $runner.ProcessId)
      }
      Write-HttpText -Response $Response -Text (New-WorkloopRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
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
        $runner = Start-WorkloopRunnerProcess -Project $project -Pair $pair
        if ($runner.Started) {
          Write-Host ("[{0}] workloop-runner started for report pid={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $runner.ProcessId)
        }
        Write-HttpText -Response $Response -Text (New-WorkloopRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
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
      $powershell = Get-AiRelayPowerShellHost
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

    if ($path -eq '/action/workloop-stop') {
      $pairDir = Get-AiRelayPairDir $project $pair
      $statusPath = Join-Path $pairDir 'workloop-runner-status.json'
      if (-not (Test-Path -LiteralPath $statusPath)) { throw "状态文件不存在：$statusPath" }
      $status = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json
      $runnerProcessId = if ($status.processId) { [int]$status.processId } else { 0 }
      if ($runnerProcessId -gt 0) {
        Stop-ProcessTreeById -ProcessId $runnerProcessId
      }
      $status.status = 'stopped'
      $status.message = '用户从面板停止了 Workloop runner。'
      $status.updatedAt = (Get-Date).ToString('o')
      Write-AiRelayJson $status $statusPath
      Write-Host ("[{0}] STOP workloop-runner project={1} pair={2} pid={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $runnerProcessId)
      Write-HttpText -Response $Response -Text (New-WorkloopRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
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
      $useCache = [string]$query['cache'] -eq '1'
      $force = [string]$query['force'] -eq '1'
      Write-Host ("[{0}] RUN summary project={1} pair={2} analyzer={3} cache={4} force={5}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $project, $pair, $analyzer, $useCache, $force)
      $runner = Start-SummaryRunnerProcess -Project $project -Pair $pair -Analyzer $analyzer -UseCache:$useCache -CacheOnly:($useCache -and -not $force) -Open
      if ($runner.Started) {
        Write-Host ("[{0}] summary-runner started pid={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $runner.ProcessId)
      }
      Write-HttpText -Response $Response -Text (New-SummaryRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
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
    if ($path -eq '/status/processes') {
      Write-HttpText -Response $Response -Text (New-ProcessDiagnosticsHtml -BaseUrl $prefix)
      return
    }
    $project = Assert-AllowedProject (Decode-Query $query['projectRoot'])
    $pair = Decode-Query $query['pair']
    Assert-AiRelayPairName $pair
    if ($path -eq '/status/cc-runner') {
      Write-HttpText -Response $Response -Text (New-CcRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
      return
    }
    if ($path -eq '/status/workloop') {
      Write-HttpText -Response $Response -Text (New-WorkloopRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
      return
    }
    if ($path -eq '/status/codex-plan') {
      Write-HttpText -Response $Response -Text (New-CodexPlanStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
      return
    }
    if ($path -eq '/status/summary') {
      Write-HttpText -Response $Response -Text (New-SummaryRunnerStatusHtml -Project $project -Pair $pair -BaseUrl $prefix)
      return
    }
    Write-HttpText -Response $Response -Text (New-ResultHtml '未知状态页' "<pre>$(Encode-Html $path)</pre>") -StatusCode 404
  } catch {
    Write-HttpText -Response $Response -Text (New-ResultHtml '状态读取失败' "<pre>$(Encode-Html $_.Exception.Message)</pre>") -StatusCode 500
  }
}

function Handle-Api {
  param(
    [System.Net.HttpListenerRequest]$Request,
    [System.Net.HttpListenerResponse]$Response
  )
  $path = [string]$Request.Url.AbsolutePath
  if ($path.Length -gt 1) {
    $path = $path.TrimEnd('/')
  }
  try {
    if ($env:NODE_ENV -eq 'production' -or $env:AI_WORKLOOP_PRODUCTION -eq '1') {
      Write-HttpJson -Response $Response -StatusCode 404 -Data ([ordered]@{
        success = $false
        error = 'Relay session scanning is disabled in production.'
      })
      return
    }
    if ($path -eq '/api/dev/relay-sessions/codex') {
      Write-HttpJson -Response $Response -Data (Get-CodexRelaySessions)
      return
    }
    if ($path -eq '/api/dev/relay-sessions/cc') {
      Write-HttpJson -Response $Response -Data (Get-ClaudeRelaySessions)
      return
    }
    Write-HttpJson -Response $Response -StatusCode 404 -Data ([ordered]@{
      success = $false
      error = "Unknown API path: $path"
    })
  } catch {
    Write-HttpJson -Response $Response -StatusCode 500 -Data ([ordered]@{
      success = $false
      error = $_.Exception.Message
    })
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
    } elseif ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath.StartsWith('/api/dev/')) {
      Handle-Api -Request $request -Response $response
    } elseif ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath.StartsWith('/status/')) {
      Handle-Status -Request $request -Response $response
    } elseif ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath -eq '/action/open') {
      Handle-Action -Request $request -Response $response
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

