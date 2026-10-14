[CmdletBinding()]
param([string]$ResultsPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
if(-not $ResultsPath){$ResultsPath=Join-Path $Root 'TestResults\regression.csv'}
$Engine=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if(-not(Test-Path -LiteralPath $Engine)){throw 'Windows PowerShell 5.1 is required.'}
$Sources=@(Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -Recurse -File)
foreach($Source in $Sources){
    $Tokens=$null;$Errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($Source.FullName,[ref]$Tokens,[ref]$Errors)
    if($Errors.Count){throw ($Source.Name+': '+($Errors|Out-String))}
}
$Tests=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File|Sort-Object Name)
if($Tests.Count -eq 0){throw 'No regression test files found.'}
$Results=@(foreach($Test in $Tests){
    $Watch=[Diagnostics.Stopwatch]::StartNew()
    $PreviousPreference=$ErrorActionPreference
    try{
        # A child writing stderr is a test result, not a reason to lose the rest of the suite.
        $ErrorActionPreference='Continue'
        $Output=@(& $Engine -NoProfile -ExecutionPolicy Bypass -STA -File $Test.FullName 2>&1)
        $Code=$LASTEXITCODE
    }finally{$ErrorActionPreference=$PreviousPreference}
    Write-Host ($Test.Name+' : '+$Code)
    if($Code -ne 0){Write-Host ($Output -join "`n")}
    [pscustomobject]@{Test=$Test.Name;ExitCode=$Code;Seconds=[math]::Round($Watch.Elapsed.TotalSeconds,2);Detail=($Output -join "`n")}
})
$Parent=Split-Path -Parent ([IO.Path]::GetFullPath($ResultsPath))
New-Item -ItemType Directory -Path $Parent -Force|Out-Null
$Results|Export-Csv -LiteralPath $ResultsPath -NoTypeInformation -Encoding UTF8
$Failed=@($Results|Where-Object ExitCode -ne 0).Count
Write-Host ('TOTAL='+$Results.Count+' FAILED='+$Failed+' PARSEFILES='+$Sources.Count)
if($Failed){throw "$Failed regression test file(s) failed. See $ResultsPath"}
