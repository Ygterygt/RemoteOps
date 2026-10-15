$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
# Proves that the package worker never opens a window/interactive session on the endpoint: runs the real PackageScript worker
# against a fake PsExec that records its exact command line, then checks the arguments and the decoded remote wrapper.
$Tokens=$null;$ParseErrors=$null
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Modules\ApplicationWorkers.ps1'),[ref]$Tokens,[ref]$ParseErrors)
$Assignment=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$PackageScript'},$true)
$Worker=$Assignment.Right.Find({param($Node)$Node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]},$true).ScriptBlock.GetScriptBlock()
$Temp=Join-Path $env:TEMP ('RemoteOpsNoUi-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $Temp -Force|Out-Null
$ArgFile=Join-Path $Temp 'psexec-args.txt'
try{
    $FakePsExec=Join-Path $Temp 'fakepsexec.cmd'
    Set-Content -LiteralPath $FakePsExec -Value ("@echo off`r`necho %*>`"$ArgFile`"`r`nexit /b 0") -Encoding ASCII
    $Forbidden='Start-Process|msg\.exe|\bmsg\s|MessageBox|Windows\.Forms|PresentationFramework|Read-Host|\bpause\b|Out-GridView|Show-Command|explorer|Add-Type|notepad|mshta|WScript\.Shell|Popup'
    foreach($File in 'install.bat','install.cmd','install.ps1','install.vbs'){
        if(Test-Path -LiteralPath $ArgFile){Remove-Item -LiteralPath $ArgFile -Force}
        $Result=& $Worker 'PC1' '\server\share\pkg' $File $FakePsExec 10 60 $false (Join-Path $Root 'Modules\FileOperations.ps1') $Temp 'INSTALL' 'NOUI-1' 10 '{}' 'DisplayName' 'X' 6 '' 0 0 0 $true $false $null
        if(-not(Test-Path -LiteralPath $ArgFile)){throw "Fake PsExec was not started for $File."}
        $Line=(Get-Content -LiteralPath $ArgFile -Raw).Trim()
        $Parts=@($Line -split '\s+')
        if($Parts[0] -cne '\\PC1'){throw "First PsExec argument must be the target: $($Parts[0])"}
        foreach($Need in '-s','-accepteula','-NonInteractive','-NoProfile','-EncodedCommand'){if($Parts -cnotcontains $Need){throw "PsExec arguments for $File lack $Need."}}
        foreach($Bad in '-i','-d','-h','-x','-u','-p','-e','-c','-f'){if($Parts -ccontains $Bad){throw "PsExec arguments for $File contain forbidden switch $Bad (visible/interactive session risk)."}}
        if($Parts -cnotcontains 'powershell.exe'){throw 'Remote command must be powershell.exe.'}
        $Index=[array]::IndexOf($Parts,'-EncodedCommand')
        $Wrapper=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Parts[$Index+1]))
        if($Wrapper -match $Forbidden){throw "Remote wrapper for $File contains a window-capable call: $($Matches[0])"}
        switch([IO.Path]::GetExtension($File)){
            '.bat'{if($Wrapper -notmatch '/d /v:off /c'){throw 'bat must run through ComSpec /d /v:off /c.'}}
            '.cmd'{if($Wrapper -notmatch '/d /v:off /c'){throw 'cmd must run through ComSpec /d /v:off /c.'}}
            '.ps1'{if($Wrapper -notmatch "powershell\.exe' -NoLogo -NoProfile -NonInteractive"){throw 'ps1 must run powershell -NonInteractive.'}}
            '.vbs'{if($Wrapper -notmatch '//B'){throw 'vbs must run cscript //B (batch mode, no dialogs).'}}
        }
    }
    # Static scan: nothing in the code base may open a visible window on a remote computer.
    $Files=@(Get-ChildItem -LiteralPath (Join-Path $Root 'Modules') -Filter '*.ps1' -File)+@(Get-ChildItem -LiteralPath (Join-Path $Root 'RemoteOps.App') -Filter '*.ps1' -File -Recurse)
    foreach($Required in @('ApplicationWorkers.ps1','RemoteOps.App.ps1','RemoteOps.Runner.ps1','RemoteOps.Deployment.ps1')){
        if(@($Files|Where-Object Name -eq $Required).Count -ne 1){throw "Required remote-facing source missing: $Required"}
    }
    $Patterns=[ordered]@{
        'Win32_Process Create'='Win32_Process.*Create|MethodName\s+Create\b'
        'Invoke-WmiMethod'='Invoke-WmiMethod'
        'PSSession/Invoke-Command'='Invoke-Command|New-PSSession|Enter-PSSession'
        'schtasks /create'='schtasks(\.exe)?\s+/create'
        'msg.exe'='\bmsg(\.exe)?\s+\*|\bmsg(\.exe)?\s+/'
        'psexec -i'='psexec[^\r\n]*\s-i\b'
        'reboot/shutdown'='Restart-Computer|Stop-Computer|\bshutdown(\.exe)?\s+/'
        'Win32_Product'='Win32_Product'
        'MessageBox on remote'='MessageBox'
    }
    $Hits=@()
    foreach($F in $Files){
        $Lines=@(Get-Content -LiteralPath $F.FullName)
        for($i=0;$i -lt $Lines.Count;$i++){
            $L=$Lines[$i]
            if($L.TrimStart().StartsWith('#')){continue}
            foreach($Name in $Patterns.Keys){
                if($L -match $Patterns[$Name]){
                    # the administrator-side WPF app is allowed its own message boxes
                    if($Name -eq 'MessageBox on remote' -and $F.FullName -in @((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),(Join-Path $Root 'RemoteOps.App\RemoteOps.PackageUi.ps1'),(Join-Path $Root 'RemoteOps.App\RemoteOps.HistoryUi.ps1'),(Join-Path $Root 'RemoteOps.App\RemoteOps.TargetGroupsUi.ps1'),(Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeUi.ps1'))){continue}
                    # Reports.ps1 only opens finished reports locally; comments/strings describing forbidden calls are allowed in this test file only
                    $Hits+=("{0}:{1} [{2}] {3}" -f $F.Name,($i+1),$Name,$L.Trim().Substring(0,[Math]::Min(100,$L.Trim().Length)))
                }
            }
        }
    }
    if($Hits.Count -gt 0){throw ("Window-capable constructs found:`n"+($Hits -join "`n"))}
    # Every Start-Process in the remote-facing code must be hidden or a local report open (.html/.csv).
    $Bad=@()
    foreach($F in $Files){
        $FileAst=[System.Management.Automation.Language.Parser]::ParseFile($F.FullName,[ref]$null,[ref]$null)
        foreach($Cmd in $FileAst.FindAll({param($N)$N -is [System.Management.Automation.Language.CommandAst] -and $N.GetCommandName() -eq 'Start-Process'},$true)){
            $Text=$Cmd.Extent.Text
            if($Text -match 'WindowStyle\s+Hidden|-WindowStyle\s+''?Hidden'){continue}
            # local report open only (the runner turns .html/.csv opens into report candidates; the GUI opens them on the administrator PC)
            if($Text -match '-FilePath\s+\$\w*(Html|Report|Csv)\w*'){continue}
            $Bad+=("{0}:{1} {2}" -f $F.Name,$Cmd.Extent.StartLineNumber,$Text.Substring(0,[Math]::Min(100,$Text.Length)))
        }
    }
    if($Bad.Count -gt 0){throw ("Start-Process without -WindowStyle Hidden:`n"+($Bad -join "`n"))}
    Write-Output 'PASS: package worker PsExec arguments (-s -accepteula, no -i/-d/-h), non-interactive remote wrapper for bat/cmd/ps1/vbs, and no window-capable construct in the code base.'
}
finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
