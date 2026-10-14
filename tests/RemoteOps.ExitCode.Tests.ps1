$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
# Start-Process -PassThru without -Wait returns a null ExitCode in Windows PowerShell 5.1 unless the handle is cached.
# The GUI must therefore cache the handle at launch and must never treat a missing code as failure.
$Source=Get-Content -LiteralPath (Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1') -Raw
if(([regex]::Matches($Source,'\[void\]\$Process\.Handle')).Count -ne 2){throw 'Both launch paths must cache the process handle.'}
if($Source -notmatch '\$null -ne \$RunExitCode'){throw 'A missing exit code must not mark the run as failed.'}
foreach($Case in @(@(0,'Completed'),@(3,'Failed'))){
    $Process=Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList '-NoLogo','-NoProfile','-Command',("Start-Sleep -Milliseconds 300; exit {0}" -f $Case[0]) -RedirectStandardOutput (Join-Path $env:TEMP 'rops-exit.out') -RedirectStandardError (Join-Path $env:TEMP 'rops-exit.err') -WindowStyle Hidden -PassThru
    [void]$Process.Handle
    while(-not $Process.HasExited){Start-Sleep -Milliseconds 100}
    $Process.WaitForExit()
    $Code=$Process.ExitCode
    if($null -eq $Code -or [int]$Code -ne [int]$Case[0]){throw "Exit code $($Case[0]) was read as [$Code]."}
}
Remove-Item (Join-Path $env:TEMP 'rops-exit.out'),(Join-Path $env:TEMP 'rops-exit.err') -Force -ErrorAction SilentlyContinue
Write-Output 'PASS: process handle cached at launch, exit codes 0 and 3 read correctly, null code never counted as failure.'
