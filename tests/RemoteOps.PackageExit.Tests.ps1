$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
# Runs the real PackageScript worker from Modules\ApplicationWorkers.ps1 against a fake PsExec to prove that the package exit code
# is the real one (a missing/empty ExitCode used to be converted to 0 = "success").
$Tokens=$null;$ParseErrors=$null
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Modules\ApplicationWorkers.ps1'),[ref]$Tokens,[ref]$ParseErrors)
$Assignment=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$PackageScript'},$true)
$Worker=$Assignment.Right.Find({param($Node)$Node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]},$true).ScriptBlock.GetScriptBlock()
$Temp=Join-Path $env:TEMP ('RemoteOpsPkgExit-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $Temp -Force|Out-Null
try{
    $FakePsExec=Join-Path $Temp 'fakepsexec.cmd'
    Set-Content -LiteralPath $FakePsExec -Value "@echo off`r`nping -n 2 127.0.0.1 >nul`r`nexit /b %FAKE_PKG_CODE%" -Encoding ASCII
    foreach($Case in @(@(0,'Success'),@(3010,'SuccessRebootRequired'),@(1603,'Failed'),@(1,'Failed'))){
        $env:FAKE_PKG_CODE=[string]$Case[0]
        $Result=& $Worker 'PC1' '\server\share\pkg' 'install.bat' $FakePsExec 10 60 $false (Join-Path $Root 'Modules\FileOperations.ps1') $Temp 'INSTALL' 'PKG-1' 10 '{}' 'DisplayName' 'X' 6 '' 0 0 0 $true $false $null
        $Result=@($Result|Where-Object{$null -ne $_ -and $null -ne $_.PSObject.Properties['ExecutionStatus']})|Select-Object -Last 1
        if([int]$Result.ExitCode -ne [int]$Case[0] -or $Result.ExecutionStatus -ne $Case[1]){throw ("Package exit code {0} was reported as ExitCode=[{1}] Status={2}." -f $Case[0],$Result.ExitCode,$Result.ExecutionStatus)}
    }
    Write-Output 'PASS: real package worker reports the true package exit code (0, 3010, 1603, 1) through a fake PsExec.'
}
finally{Remove-Item Env:\FAKE_PKG_CODE -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
