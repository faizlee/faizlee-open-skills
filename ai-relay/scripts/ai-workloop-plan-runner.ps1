param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$Pair,
  [Parameter(Mandatory=$true)][string]$CodexSessionId,
  [Parameter(Mandatory=$true)][string]$Goal,
  [int]$MaxRounds = 10
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_ai-relay-common.ps1"

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

function Write-PlanStatus {
  param(
    [string]$Status,
    [string]$Message,
    [int]$ExitCode = 0
  )
  Write-AiRelayJson ([ordered]@{
    pairId = $Pair
    projectRoot = $ProjectRoot
    status = $Status
    message = $Message
    exitCode = $ExitCode
    updatedAt = (Get-Date).ToString('o')
    processId = $PID
    planPromptPath = $script:planPromptPath
    planReplyPath = $script:planReplyPath
    inboxPath = $script:inboxPath
    logPath = $script:planLogPath
  }) $script:statusPath
}

function Set-WorkloopPlannerGoalTerminal {
  param(
    [ValidateSet('completed','stopped')][string]$Status,
    [string]$Reason,
    [string]$LastNextInstruction,
    [string]$Decision = ''
  )
  if (-not (Test-Path -LiteralPath $script:goalPath)) { return }
  try {
    $goalJson = Get-Content -LiteralPath $script:goalPath -Raw -Encoding utf8 | ConvertFrom-Json
    $goalJson.status = $Status
    $goalJson.stopReason = $Reason
    if (-not [string]::IsNullOrWhiteSpace($Decision)) {
      $goalJson.lastDecision = $Decision
    }
    $goalJson.lastNextInstruction = $LastNextInstruction
    $goalJson.updatedAt = (Get-Date).ToString('o')
    Write-AiRelayJson $goalJson $script:goalPath
    Add-AiRelayLog -PairDir $script:pairDir -Event 'workloop-planner-terminal' -Detail "status=$Status`n$Reason"
  } catch {
  }
}

Push-Location $ProjectRoot
try {
  Assert-AiRelayPairName $Pair
  $pairDir = Get-AiRelayPairDir $ProjectRoot $Pair
  if (-not (Test-Path -LiteralPath $pairDir)) { throw "Pair 不存在：$pairDir" }
  $script:pairDir = $pairDir

  $script:statusPath = Join-Path $pairDir 'codex-plan-status.json'
  $script:planPromptPath = Join-Path $pairDir 'codex-plan-prompt.md'
  $script:planReplyPath = Join-Path $pairDir 'codex-plan-reply.md'
  $script:planLogPath = Join-Path $pairDir 'codex-plan.log'
  $script:inboxPath = Join-Path $pairDir 'cc-inbox.md'
  $script:goalPath = Join-Path $pairDir 'goal.json'

  Write-Host 'Agent Workloop Codex planner'
  Write-Host "Pair: $Pair"
  Write-Host "Project: $ProjectRoot"
  Write-Host "Codex session: $CodexSessionId"
  Write-Host ''

  Write-PlanStatus -Status 'running' -Message 'Codex 正在规划任务。'

  $codex = Get-Command codex -ErrorAction SilentlyContinue
  if (-not $codex) { throw 'codex CLI not found in PATH.' }
  if (-not (Test-Path -LiteralPath $planPromptPath)) { throw "规划 prompt 不存在：$planPromptPath" }

  Write-Host '调用 Codex 生成给 Claude Code 的下一轮任务...'
  Write-Host ''

  $oldErrorActionPreference = $ErrorActionPreference
  $oldNativePreference = $null
  $hadNativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
  if ($hadNativePreference) { $oldNativePreference = $PSNativeCommandUseErrorActionPreference }
  try {
    $ErrorActionPreference = 'Continue'
    if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $false }
    $codexOutput = Get-Content -LiteralPath $planPromptPath -Raw -Encoding utf8 |
      & $codex.Source exec -C $ProjectRoot resume --ignore-user-config -c 'sandbox_mode="read-only"' -o $planReplyPath $CodexSessionId - 2>&1 |
      Tee-Object -FilePath $planLogPath |
      Out-String
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
    if ($hadNativePreference) { $global:PSNativeCommandUseErrorActionPreference = $oldNativePreference }
  }
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    Write-PlanStatus -Status 'failed' -Message "Codex 规划失败。ExitCode=$exitCode" -ExitCode $exitCode
    throw "Codex 规划失败。ExitCode=$exitCode`n$codexOutput"
  }

  $planReply = Read-AiRelayTextFile $planReplyPath
  if ([string]::IsNullOrWhiteSpace($planReply)) {
    $planReply = $codexOutput
    Set-Content -LiteralPath $planReplyPath -Value $planReply -Encoding utf8
  }
  if ([string]::IsNullOrWhiteSpace($planReply)) {
    throw 'Codex 规划结果为空。'
  }

  Set-Content -LiteralPath (Join-Path $pairDir 'codex-reply.md') -Value $planReply -Encoding utf8
  $taskMatch = [regex]::Match($planReply, '## 给 Claude Code 的任务\s*([\s\S]*?)(?=\r?\n## |\z)')
  $taskText = if ($taskMatch.Success) { $taskMatch.Groups[1].Value.Trim() } else { $planReply.Trim() }
  if ([string]::IsNullOrWhiteSpace($taskText)) {
    throw 'Codex 规划结果为空，无法写入 cc-inbox.md。'
  }

  $workloopDecision = Get-AiRelayWorkloopDecision -Text $planReply -FallbackText $taskText
  Add-AiRelayLog -PairDir $pairDir -Event 'workloop-decision' -Detail "source=$($workloopDecision.Source)`ndecision=$($workloopDecision.Decision)`nshouldWriteInbox=$($workloopDecision.ShouldWriteInbox)`nreason=$($workloopDecision.Reason)"

  if ($workloopDecision.Decision -eq 'completed') {
    Set-Content -LiteralPath (Join-Path $pairDir 'codex-reply.md') -Value $planReply -Encoding utf8
    Set-WorkloopPlannerGoalTerminal -Status 'completed' -Reason $workloopDecision.Reason -LastNextInstruction $workloopDecision.NextTask -Decision '接受。'
    Write-PlanStatus -Status 'completed' -Message 'Codex 规划结果表示无需下一轮任务，goal 已自动标记 completed。'
    Write-Host ''
    Write-Host 'Codex 表示无需下一轮任务，goal 已自动标记 completed。' -ForegroundColor Green
    Write-Host ''
    Write-Host $workloopDecision.NextTask
    exit 0
  }

  if ($workloopDecision.Decision -in @('needs_user','blocked')) {
    Set-Content -LiteralPath (Join-Path $pairDir 'codex-reply.md') -Value $planReply -Encoding utf8
    Set-WorkloopPlannerGoalTerminal -Status 'stopped' -Reason $workloopDecision.Reason -LastNextInstruction $workloopDecision.NextTask -Decision '需要用户介入'
    Write-PlanStatus -Status 'completed' -Message 'Codex 规划未给出可自动继续的结构化任务，goal 已停止等待用户。'
    Write-Host ''
    Write-Host 'Codex 规划未给出可自动继续的结构化任务，goal 已停止等待用户。' -ForegroundColor Yellow
    Write-Host ''
    Write-Host $workloopDecision.NextTask
    exit 0
  }

  if ($workloopDecision.Decision -ne 'continue' -or -not $workloopDecision.ShouldWriteInbox) {
    Set-WorkloopPlannerGoalTerminal -Status 'stopped' -Reason 'Structured decision did not allow writing cc-inbox.md.' -LastNextInstruction $workloopDecision.NextTask -Decision '需要用户介入'
    Write-PlanStatus -Status 'completed' -Message 'Workloop decision did not allow writing cc-inbox.md; stopped for user review.'
    exit 0
  }

  $taskText = $workloopDecision.NextTask
  Set-Content -LiteralPath $inboxPath -Value $taskText -Encoding utf8
  Add-AiRelayLog -PairDir $pairDir -Event 'dashboard-codex-plan' -Detail "Goal: $Goal`nMaxRounds=$MaxRounds`nCodexSession=$CodexSessionId"
  [void](Copy-AiRelayText $taskText)

  if (Test-Path -LiteralPath $script:goalPath) {
    try {
      $goalJson = Get-Content -LiteralPath $script:goalPath -Raw -Encoding utf8 | ConvertFrom-Json
      $goalJson.status = 'planned'
      $goalJson.updatedAt = (Get-Date).ToString('o')
      Write-AiRelayJson $goalJson $script:goalPath
    } catch {
    }
  }

  Write-PlanStatus -Status 'completed' -Message 'Codex 已完成规划，并已写入 cc-inbox.md。'
  Write-Host ''
  Write-Host 'Codex 已完成规划，并已写入 cc-inbox.md。' -ForegroundColor Green
  Write-Host ''
  Write-Host $taskText
  exit 0
} catch {
  Write-Host ''
  Write-Host "Codex planner failed: $($_.Exception.Message)" -ForegroundColor Red
  try { Write-PlanStatus -Status 'failed' -Message $_.Exception.Message -ExitCode 1 } catch {}
  exit 1
} finally {
  Pop-Location
}
