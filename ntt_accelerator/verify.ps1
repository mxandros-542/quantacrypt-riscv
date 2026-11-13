param([switch]$Setup)
$ErrorActionPreference = 'Stop'
$projectWindows = $PSScriptRoot
$projectLinux = (& wsl.exe wslpath -a $projectWindows).Trim()
if ($LASTEXITCODE -ne 0) { throw 'WSL could not resolve the project path.' }
if ($Setup) {
    & wsl.exe --cd $projectLinux -e sh tools/setup_iverilog.sh
    if ($LASTEXITCODE -ne 0) { throw 'Local Icarus setup failed.' }
}
& wsl.exe --cd $projectLinux -e python3 tools/run_tests.py
if ($LASTEXITCODE -ne 0) { throw 'Verification failed; see build/logs and the JSON report.' }
