param(
  [switch]$SkipDryRun
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $root 'scripts'
$required = @(
  '_ai-relay-common.ps1',
  'ai-workloop-dashboard.ps1',
  'ai-workloop-dashboard-server.ps1',
  'ai-workloop-cc-runner.ps1',
  'ai-workloop-project.ps1',
  'ai-workloop-rebind-cc.ps1',
  'ai-workloop-summary.ps1',
  'ai-workloop.ps1',
  'ai-relay-bind-cc.ps1',
  'ai-relay-bind-codex.ps1',
  'ai-relay-codex.ps1',
  'ai-relay-cc.ps1',
  'ai-relay-use.ps1',
  'ai-relay-current.ps1',
  'ai-relay-list.ps1',
  'ai-relay-open.ps1',
  'ai-relay-export.ps1',
  'ai-relay-goal.ps1',
  'ai-relay-review.ps1',
  'ai-relay-init-skill.ps1'
)

foreach ($name in $required) {
  $path = Join-Path $scripts $name
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing script: $path"
  }
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors) {
    throw "PowerShell parse failed for $name`: $($errors[0].Message)"
  }
}

$powershellExe = Get-Command powershell.exe -ErrorAction SilentlyContinue
if ($powershellExe) {
  $tmpParse = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-relay-ps5-parse-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmpParse | Out-Null
  try {
    foreach ($name in $required) {
      $path = Join-Path $scripts $name
      $tmpPath = Join-Path $tmpParse $name
      $content = Get-Content -LiteralPath $path -Raw -Encoding utf8
      $encoding = [System.Text.UTF8Encoding]::new($true)
      [System.IO.File]::WriteAllText($tmpPath, $content, $encoding)
      $encodedPath = $tmpPath.Replace("'", "''")
      $command = "`$tokens=`$null; `$errors=`$null; [System.Management.Automation.Language.Parser]::ParseFile('$encodedPath',[ref]`$tokens,[ref]`$errors) > `$null; if (`$errors) { `$errors[0].Message; exit 1 }"
      & $powershellExe.Source -NoProfile -ExecutionPolicy Bypass -Command $command
      if ($LASTEXITCODE -ne 0) {
        throw "Windows PowerShell parse failed for $name."
      }
    }
  } finally {
    Remove-Item -LiteralPath $tmpParse -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$ccText = Get-Content -LiteralPath (Join-Path $scripts 'ai-relay-cc.ps1') -Raw -Encoding utf8
foreach ($forbidden in @('--last', 'codex-with-cc', 'subagent')) {
  if ($ccText.Contains($forbidden)) {
    throw "Forbidden token found in ai-relay-cc.ps1: $forbidden"
  }
}
if (-not $ccText.Contains('codexSessionId')) {
  throw "ai-relay-cc.ps1 must use explicit codexSessionId."
}
if (-not ($ccText.Contains("'--sandbox', 'read-only'") -or $ccText.Contains('sandbox_mode="read-only"'))) {
  throw "ai-relay-cc.ps1 must use read-only sandbox."
}
if (-not ($ccText.Contains("'--output-last-message'") -or $ccText.Contains("'-o'"))) {
  throw "ai-relay-cc.ps1 must write output-last-message."
}

if (-not $SkipDryRun) {
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-relay-verify-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    Push-Location $tmp
    & (Join-Path $scripts 'ai-relay-bind-cc.ps1') -Pair 'verify-dryrun' -Task 'verify dry run' -Force | Out-Null
    $pairDir = Join-Path $tmp '.ai-relay\pairs\verify-dryrun'
    foreach ($name in @('bind-request.md','cc-inbox.md','cc-report.md','relay-log.md')) {
      if (-not (Test-Path -LiteralPath (Join-Path $pairDir $name))) {
        throw "Dry-run missing file: $name"
      }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $pairDir 'codex-reply.read.md'))) {
      throw "Dry-run missing file: codex-reply.read.md"
    }
    $sentinel = "preserve report $(New-Guid)"
    Set-Content -LiteralPath (Join-Path $pairDir 'cc-report.md') -Value $sentinel -Encoding utf8
    @{
      pairId = 'verify-dryrun'
      projectRoot = $tmp
      task = 'verify dry run'
      codexSessionId = 'codex-session-for-verify'
      ccSessionId = ''
      ccSessionName = ''
      ccInboxPath = Join-Path $pairDir 'cc-inbox.md'
      ccReportPath = Join-Path $pairDir 'cc-report.md'
      codexReplyPath = Join-Path $pairDir 'codex-reply.md'
      role = 'commander'
      boundAt = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $pairDir 'pair.json') -Encoding utf8
    & (Join-Path $scripts 'ai-workloop-rebind-cc.ps1') -Pair 'verify-dryrun' -CcSessionId 'claude-session-for-verify' | Out-Null
    $rebuilt = Get-Content -LiteralPath (Join-Path $pairDir 'pair.json') -Raw -Encoding utf8 | ConvertFrom-Json
    if ($rebuilt.ccSessionId -ne 'claude-session-for-verify') {
      throw "Rebind dry-run did not update ccSessionId."
    }
    if ($rebuilt.codexSessionId -ne 'codex-session-for-verify') {
      throw "Rebind dry-run should preserve codexSessionId."
    }
    $reportAfterRebind = Get-Content -LiteralPath (Join-Path $pairDir 'cc-report.md') -Raw -Encoding utf8
    if ($reportAfterRebind -notmatch [regex]::Escape($sentinel)) {
      throw "Rebind dry-run should preserve cc-report.md."
    }
    $bindAfterRebind = Get-Content -LiteralPath (Join-Path $pairDir 'bind-request.md') -Raw -Encoding utf8
    if (-not $bindAfterRebind.Contains('ccSessionId: claude-session-for-verify')) {
      throw "Rebind dry-run did not write ccSessionId into bind-request.md."
    }
  } finally {
    Pop-Location
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "AI Relay verify OK"
