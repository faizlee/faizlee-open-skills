@echo off
setlocal

set "AI_RELAY_BIN=%USERPROFILE%\.ai-tools\bin"
set "AI_RELAY_SERVER=%AI_RELAY_BIN%\ai-workloop-dashboard-server.ps1"
set "AI_RELAY_URL=http://127.0.0.1:17877/"

if not exist "%AI_RELAY_SERVER%" (
  echo Missing AI Relay dashboard server:
  echo %AI_RELAY_SERVER%
  echo.
  pause
  exit /b 1
)

echo Restarting AI Relay dashboard...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$script=$env:AI_RELAY_SERVER; $url=$env:AI_RELAY_URL; $current=$PID; $old=@(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $current -and $_.CommandLine -and $_.CommandLine -like ('*' + $script + '*') }); foreach($p in $old){ try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Write-Host ('Stopped old AI Relay server PID ' + $p.ProcessId) } catch { Write-Host ('Could not stop PID ' + $p.ProcessId + ': ' + $_.Exception.Message) } }; Start-Sleep -Milliseconds 500; $proc=Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-Open') -PassThru; Write-Host ('Started AI Relay server PID ' + $proc.Id); Start-Sleep -Seconds 2; try { $r=Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 8; Write-Host ('AI Relay dashboard OK: HTTP ' + $r.StatusCode) } catch { Write-Host ('AI Relay dashboard may still be starting: ' + $_.Exception.Message) }"

echo.
echo AI Relay dashboard:
echo %AI_RELAY_URL%
echo.
echo This window can be closed after the dashboard opens.
pause
