@echo off
rem Strata backup entry point (cmd.exe, double-click, or a shortcut).
rem Place this file directly in %STRATA_HOME% (the folder holding terminal\,
rem models\, patches\) -- it resolves everything relative to its own location.
rem The main entry is strata-preset.ps1; this is the plain-command fallback that also
rem works where PowerShell scripts are restricted.
rem
rem   strata-launch.cmd                  start the default tier (64K)
rem   strata-launch.cmd <tier>           start 32k | 64k | 128k | 128kv
rem   strata-launch.cmd --status         what is serving now
rem   strata-launch.cmd --stop           stop, and restore the GPU power limit
rem   strata-launch.cmd --plan [tier]    what would happen; changes nothing
rem   strata-launch.cmd --list           list the presets
rem   strata-launch.cmd -- <args>        pass the rest straight to `strata launch`
rem
rem GPU power: this PC's USB display and keyboard dropped when the card stepped from idle
rem to full load. `strata launch` itself now caps the card (STRATA_GPU_POWER_LIMIT) and
rem `--stop` restores it, so this script only passes the variable through -- it does not
rem call nvidia-smi itself any more. Setting a limit needs administrator rights; without
rem them Strata prints one line and serves uncapped.
setlocal
set "PYTHONUTF8=1"
set "HERE=%~dp0"
set "PATH=%HERE%terminal\current\bin;%PATH%"
set "DEFAULT_TIER=64k"

rem Only the download/update steps need the proxy; starting an installed model does not.
set "HTTPS_PROXY=http://127.0.0.1:7890"
set "HTTP_PROXY=http://127.0.0.1:7890"

rem GPU power is NOT capped any more. A 200 W cap was tried against the USB
rem disconnect problem and did not stop it (13 events on 200 W), so the card runs at
rem its own 350 W default. The patch that reads STRATA_GPU_POWER_LIMIT is still
rem installed; set that variable yourself if you ever want to experiment again.

if "%~1"=="--status" goto status
if "%~1"=="--stop" goto stop
if "%~1"=="--plan" goto plan
if "%~1"=="--list" goto list
if "%~1"=="--" goto passthrough

rem ---- tier -> preset name (keep in step with strata-preset.ps1) ----
set "TIER=%~1"
if "%TIER%"=="" set "TIER=%DEFAULT_TIER%"
if /i "%TIER%"=="32k"   set "PRESET=IQ2_XS 32K"
if /i "%TIER%"=="64k"   set "PRESET=IQ2_XS 64K"
if /i "%TIER%"=="128k"  set "PRESET=IQ2_XS 128K"
if /i "%TIER%"=="256k"  set "PRESET=IQ2_XS 256K"
if not defined PRESET goto badtier

echo Starting preset "%PRESET%"...
strata launch --preset "%PRESET%" --restart --no-tui
if errorlevel 1 (
  echo Launch failed. Run `strata launch --stop` if a different model is still serving.
  exit /b 1
)
echo.
echo Serving at http://127.0.0.1:8080   (Anthropic clients: no /v1 at the end)
echo Stop with: strata-launch.cmd --stop
goto :eof

:badtier
echo Unknown tier "%TIER%". Use 32k, 64k, 128k or 128kv.
echo List them with: strata-launch.cmd --list
exit /b 2

:status
strata launch --status
goto :eof

:stop
strata launch --stop
goto :eof

:list
strata launch --list-presets
goto :eof

:plan
set "TIER=%~2"
if "%TIER%"=="" set "TIER=%DEFAULT_TIER%"
if /i "%TIER%"=="32k"   set "PRESET=IQ2_XS 32K"
if /i "%TIER%"=="64k"   set "PRESET=IQ2_XS 64K"
if /i "%TIER%"=="128k"  set "PRESET=IQ2_XS 128K"
if /i "%TIER%"=="256k"  set "PRESET=IQ2_XS 256K"
if not defined PRESET goto badtier
strata launch --preset "%PRESET%" --plan
goto :eof

:passthrough
rem `strata-launch.cmd -- --model q2_0 --context 32k` and anything else the CLI accepts
shift
strata launch %*
goto :eof
