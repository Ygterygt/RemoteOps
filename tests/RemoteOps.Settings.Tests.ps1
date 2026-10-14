$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
# Profile store, saved profiles/passwords and settings.json edge cases (empty/corrupt/partial files), using the real functions of RemoteOps.App.ps1.
$Tokens=$null;$Errs=$null
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$Tokens,[ref]$Errs)
foreach($Name in 'T','Get-OptionalPropertyValue','Protect-ProfilePassword','Unprotect-ProfilePassword','ConvertTo-ProfileStoreRows','Load-ProfileStore','Save-ProfileStore','Get-SavedSetting','Save-AppSetting','Get-SavedParallelism','Get-SavedBoolSetting','Get-CleanupUserNameCheck','Update-CleanupPreview','Save-ProfileFromForm','Get-TargetList'){
    $Fn=$Ast.Find({param($N)$N -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true)
    if($null -eq $Fn){throw "Function $Name not found in RemoteOps.App.ps1"}
    . ([scriptblock]::Create($Fn.Extent.Text))
}
function Register-AOModule {param($Name,$Version,$MinimumHostApiVersion,$SourcePath,$Initializer)}
function Register-AOModuleOperation {param($ModuleName,$Name,$DisplayName,$EntryPointName,$Handler)}
. (Join-Path $Root 'Modules\FileOperations.ps1')
$script:Log=@();function Write-AppLog{param([string]$Message)$script:Log+=$Message}
function Refresh-ProfileList{};function Update-PasswordState{}
$Temp=Join-Path $env:TEMP ('RemoteOpsSettings-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $Temp -Force|Out-Null
try{
    # ---- settings.json: missing / empty / corrupt / wrong shape / partial
    $script:SettingsPath=Join-Path $Temp 'sub\settings.json'
    if((Get-SavedParallelism) -ne 1 -or (Get-SavedSetting -Name 'CleanupPackageLogs' -Default $false) -ne $false){throw 'Missing settings file must give defaults.'}
    New-Item -ItemType Directory -Path (Split-Path $script:SettingsPath) -Force|Out-Null
    foreach($Content in @('','   ','{','garbage','null','5','[1,2]','{"Parallelism":null}','{"Other":1}')){
        [IO.File]::WriteAllText($script:SettingsPath,$Content)
        if((Get-SavedParallelism) -ne 1){throw "Settings content '$Content' must give Parallelism 1."}
        if((Get-SavedSetting -Name 'CleanupPackageLogs' -Default $false) -ne $false){throw "Settings content '$Content' must keep cleanup disabled."}
    }
    foreach($Case in @(@('{"Parallelism":0}',1),@('{"Parallelism":11}',1),@('{"Parallelism":"x"}',1),@('{"Parallelism":"4"}',4),@('{"Parallelism":10}',10),@('{"Parallelism":1}',1),@('{"Parallelism":-3}',1),@('{"Parallelism":2.2}',2))){
        [IO.File]::WriteAllText($script:SettingsPath,$Case[0])
        if((Get-SavedParallelism) -ne $Case[1]){throw "Parallelism $($Case[0]) must read as $($Case[1]), got $(Get-SavedParallelism)."}
    }
    # a safety switch is on only for a real JSON true
    foreach($Case in @(@('{"CleanupPackageLogs":true}',$true),@('{"CleanupPackageLogs":false}',$false),@('{"CleanupPackageLogs":"false"}',$false),@('{"CleanupPackageLogs":"true"}',$false),@('{"CleanupPackageLogs":1}',$false),@('{"CleanupPackageLogs":null}',$false),@('{}',$false),@('garbage',$false))){
        [IO.File]::WriteAllText($script:SettingsPath,$Case[0])
        if((Get-SavedBoolSetting -Name 'CleanupPackageLogs') -ne $Case[1]){throw "CleanupPackageLogs $($Case[0]) must read as $($Case[1])."}
    }    # merge: saving one key keeps the other; a corrupt file is replaced by valid JSON
    [IO.File]::WriteAllText($script:SettingsPath,'{"Parallelism":3}')
    Save-AppSetting -Name 'CleanupPackageLogs' -Value $true
    if((Get-SavedParallelism) -ne 3 -or (Get-SavedSetting -Name 'CleanupPackageLogs' -Default $false) -ne $true){throw 'Save-AppSetting must merge with existing keys.'}
    Save-AppSetting -Name 'Parallelism' -Value 5
    if((Get-SavedParallelism) -ne 5 -or (Get-SavedSetting -Name 'CleanupPackageLogs' -Default $false) -ne $true){throw 'Updating Parallelism must keep CleanupPackageLogs.'}
    [IO.File]::WriteAllText($script:SettingsPath,'{broken')
    Save-AppSetting -Name 'CleanupPackageLogs' -Value $false
    [void](Get-Content -LiteralPath $script:SettingsPath -Raw|ConvertFrom-Json)
    if(Test-Path -LiteralPath ($script:SettingsPath+'.tmp')){throw 'Temporary settings file must not be left behind.'}

    # ---- domains.json: empty / corrupt / single object / array / legacy column arrays
    $script:ProfilePath=Join-Path $Temp 'domains.json'
    $script:Profiles=New-Object System.Collections.ArrayList
    function Load-Json([string]$Content){$script:Profiles.Clear();$script:Log=@();[IO.File]::WriteAllText($script:ProfilePath,$Content);Load-ProfileStore}
    Load-Json '';        if($script:Profiles.Count -ne 0){throw 'Empty profile file must give no profiles.'}
    Load-Json '[]';      if($script:Profiles.Count -ne 0 -or $script:Log.Count -ne 0){throw 'Empty array must give no profiles and no error.'}
    Load-Json 'garbage'; if($script:Profiles.Count -ne 0 -or @($script:Log|Where-Object{$_ -match 'Could not load'}).Count -ne 1){throw 'Corrupt profile file must be reported once and give no profiles.'}
    Load-Json '{"Domain":"D1","UserName":"u1","ProtectedPassword":"","IsMain":true}'
    if($script:Profiles.Count -ne 1 -or $script:Log.Count -ne 0){throw "Single profile object must load without an error log (log: $($script:Log -join '|'))."}
    Load-Json '[{"Domain":"D1","UserName":"u1","ProtectedPassword":"","IsMain":true},{"Domain":"D2","UserName":"u2","ProtectedPassword":"x","IsMain":false},{"Domain":"","UserName":"","ProtectedPassword":"","IsMain":false}]'
    if($script:Profiles.Count -ne 2 -or $script:Log.Count -ne 0){throw 'Array of profiles must load (blank rows skipped).'}
    Load-Json '{"Domain":["D1","D2"],"UserName":["u1","u2"],"ProtectedPassword":["",""],"IsMain":[true,false]}'
    if($script:Profiles.Count -ne 2){throw 'Legacy column-array profile store must be recovered.'}
    $Resaved=Get-Content -LiteralPath $script:ProfilePath -Raw|ConvertFrom-Json;if(@($Resaved).Count -ne 2 -or $Resaved -isnot [array]){throw 'Recovered legacy store must be re-saved as rows.'}

    # ---- password handling
    $Threw=$false;try{[void](Unprotect-ProfilePassword -ProtectedPassword 'not-a-dpapi-blob')}catch{$Threw=$true;if($_.Exception.Message -notmatch 'Ekle'){throw 'Unreadable saved password must give the guidance message.'}}
    if(-not $Threw){throw 'Unreadable saved password must throw.'}
    $Secure=ConvertTo-SecureString 'Pa55-w0rd' -AsPlainText -Force
    $Protected=Protect-ProfilePassword $Secure
    $Back=[Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Unprotect-ProfilePassword -ProtectedPassword $Protected)))
    if($Back -ne 'Pa55-w0rd'){throw 'Password protect/unprotect round trip failed.'}

    # ---- Save-ProfileFromForm: add, update keeps password, password refresh, Main switch, validation
    $script:Profiles=New-Object System.Collections.ArrayList
    $Pw=New-Object psobject -Property @{SecurePassword=(New-Object System.Security.SecureString)}
    Add-Member -InputObject $Pw -MemberType ScriptMethod -Name Clear -Value {$this.SecurePassword=(New-Object System.Security.SecureString)}
    $script:PasswordInput=$Pw
    $script:DomainInput=New-Object psobject -Property @{Text='CORP'};$script:UsernameInput=New-Object psobject -Property @{Text='svc.one'}
    $script:MainProfileInput=New-Object psobject -Property @{IsChecked=$false}
    $script:ProfileList=New-Object psobject -Property @{SelectedItem=$null}
    $Threw=$false;try{Save-ProfileFromForm}catch{$Threw=$true};if(-not $Threw){throw 'A non-Main profile without a password must be refused.'}
    $script:PasswordInput.SecurePassword=ConvertTo-SecureString 'first' -AsPlainText -Force
    Save-ProfileFromForm
    if($script:Profiles.Count -ne 1 -or [string]::IsNullOrWhiteSpace($script:Profiles[0].ProtectedPassword)){throw 'Profile with password must be stored.'}
    $FirstBlob=$script:Profiles[0].ProtectedPassword
    $script:UsernameInput.Text='CORP\svc.one';$script:DomainInput.Text=''
    Save-ProfileFromForm   # same profile written as DOMAIN\user, no new password
    if($script:Profiles.Count -ne 1 -or $script:Profiles[0].ProtectedPassword -ne $FirstBlob){throw 'Updating without a new password must keep the saved password and not duplicate the profile.'}
    $script:PasswordInput.SecurePassword=ConvertTo-SecureString 'second' -AsPlainText -Force
    Save-ProfileFromForm
    if($script:Profiles[0].ProtectedPassword -eq $FirstBlob){throw 'Entering a new password must replace the saved one.'}
    $script:DomainInput.Text='CORP';$script:UsernameInput.Text='main.user';$script:MainProfileInput.IsChecked=$true
    Save-ProfileFromForm   # Main profile needs no password
    $script:UsernameInput.Text='other.main';Save-ProfileFromForm
    if(@($script:Profiles|Where-Object{$_.IsMain}).Count -ne 1 -or -not ($script:Profiles|Where-Object{$_.UserName -eq 'other.main'}).IsMain){throw 'Only one Main profile may exist; the newest Main wins.'}
    if($script:Profiles.Count -ne 3){throw 'Three distinct profiles expected.'}
    $Stored=Get-Content -LiteralPath $script:ProfilePath -Raw -Encoding UTF8|ConvertFrom-Json
    if(@($Stored).Count -ne 3){throw 'Profile store file must contain the three profiles.'}
    $script:DomainInput.Text='';$Threw=$false;try{Save-ProfileFromForm}catch{$Threw=$true};if(-not $Threw){throw 'Empty domain must be refused.'}

    # ---- cleanup preview warns for unsafe user names
    $script:CleanupPreview=New-Object psobject -Property @{Text=''}
    $script:ProfileList.SelectedItem=[pscustomobject]@{Domain='CORP';UserName='admin'}
    Update-CleanupPreview
    if($script:CleanupPreview.Text -notmatch 'YAPILMAZ'){throw "Unsafe user name 'admin' must produce the not-cleaned warning."}
    $script:ProfileList.SelectedItem=[pscustomobject]@{Domain='CORP';UserName='yigitery0'}
    Update-CleanupPreview
    if($script:CleanupPreview.Text -notmatch 'yigitery0' -or $script:CleanupPreview.Text -match 'YAPILMAZ'){throw 'Safe user name must show the matching pattern.'}
    $script:ProfileList.SelectedItem=$null;Update-CleanupPreview
    if([string]::IsNullOrWhiteSpace($script:CleanupPreview.Text)){throw 'No selected profile must still give a hint.'}
    # ---- target list parsing
    $L=@(Get-TargetList -Text "pc1, PC1;pc2`r`n pc3`t")
    if($L.Count -ne 3){throw "Target list must split on separators and de-duplicate case-insensitively (got $($L -join '|'))."}
    if(@(Get-TargetList -Text '').Count -ne 0 -or @(Get-TargetList -Text $null).Count -ne 0){throw 'Empty target text must give no targets.'}
    Write-Output 'PASS: settings.json (missing/empty/corrupt/partial, merge, Parallelism limits), domains.json (empty/corrupt/single/array/legacy), password refresh, Main switch, undecryptable password, cleanup preview, target parsing.'
}
finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
