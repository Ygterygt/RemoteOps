# Saved package definitions. No endpoint operations are performed by this library.
function Get-RemoteOpsPackageValue {
    param($Object,[string]$Name,$Default=$null)
    if($null -eq $Object){return $Default}
    if($Object -is [System.Collections.IDictionary]){if($Object.Contains($Name)){return $Object[$Name]};return $Default}
    $Property=$Object.PSObject.Properties[$Name]
    if($null -eq $Property){return $Default};return $Property.Value
}
function New-RemoteOpsPackageAction {
    param([string]$Mode='Version controlled')
    return [PSCustomObject]@{Enabled=$false;PackagePath='';PackageFile='';SearchType='DisplayName exact';Application='';RegistryKey='';CheckMode=$Mode}
}
function New-RemoteOpsPackageDefinition {
    param([string]$Name='')
    $Now=(Get-Date).ToString('o')
    return [PSCustomObject]@{Schema='RemoteOps.Package/2';Id=[guid]::NewGuid().ToString('D');Revision=1;Name=$Name;ApplicationKey=$Name.Trim().ToLowerInvariant();Category='';Description='';TargetVersion='';DowngradeVersion='';CreatedAt=$Now;UpdatedAt=$Now;CollectLogs=$false;DowngradeEnabled=$false;Install=(New-RemoteOpsPackageAction);Uninstall=(New-RemoteOpsPackageAction 'Presence only');Downgrade=(New-RemoteOpsPackageAction)}
}
function Copy-RemoteOpsPackageDefinition {
    param([Parameter(Mandatory=$true)]$Definition,[switch]$NewIdentity)
    $Copy=New-RemoteOpsPackageDefinition
    foreach($Key in @('Schema','Id','Revision','Name','ApplicationKey','Category','Description','TargetVersion','DowngradeVersion','CreatedAt','UpdatedAt','CollectLogs','DowngradeEnabled')){
        $Copy.$Key=Get-RemoteOpsPackageValue $Definition $Key $Copy.$Key
    }
    foreach($Action in @('Install','Uninstall','Downgrade')){
        $Source=Get-RemoteOpsPackageValue $Definition $Action
        foreach($Key in @('Enabled','PackagePath','PackageFile','SearchType','Application','RegistryKey','CheckMode')){
            $Copy.$Action.$Key=Get-RemoteOpsPackageValue $Source $Key $Copy.$Action.$Key
        }
    }
    if((Get-RemoteOpsPackageValue $Definition Schema '') -eq 'RemoteOps.Package/1'){
        $Copy.Schema='RemoteOps.Package/2'
        if($Copy.DowngradeEnabled){
            foreach($Key in @('Enabled','PackagePath','PackageFile','SearchType','Application','RegistryKey','CheckMode')){$Copy.Downgrade.$Key=$Copy.Install.$Key}
            $Copy.Downgrade.Enabled=$true;$Copy.Downgrade.CheckMode='Version controlled';$Copy.DowngradeVersion=$Copy.TargetVersion
        }
    }
    if($NewIdentity){$Copy.Id=[guid]::NewGuid().ToString('D');$Copy.Revision=1;$Copy.CreatedAt=(Get-Date).ToString('o');$Copy.UpdatedAt=$Copy.CreatedAt}
    return $Copy
}
function Test-RemoteOpsPackageDefinition {
    param([Parameter(Mandatory=$true)]$Definition,[ValidateSet('','Install','Uninstall','Downgrade')][string]$Action='')
    if((Get-RemoteOpsPackageValue $Definition Schema '') -eq 'RemoteOps.Package/1'){$Definition=Copy-RemoteOpsPackageDefinition $Definition}
    $Errors=New-Object 'System.Collections.Generic.List[object]'
    $Add={param($Field,$Message)$Errors.Add([PSCustomObject]@{Field=$Field;Message=$Message})}
    foreach($Field in @('Schema','Id','Name','ApplicationKey','Category','Description','TargetVersion','DowngradeVersion','CreatedAt','UpdatedAt')){
        if((Get-RemoteOpsPackageValue $Definition $Field '') -isnot [string]){& $Add $Field 'Use a JSON string.'}
    }
    if((Get-RemoteOpsPackageValue $Definition Schema '') -cne 'RemoteOps.Package/2'){& $Add Schema 'Unsupported package schema.'}
    $Id=[guid]::Empty
    if(-not[guid]::TryParse([string](Get-RemoteOpsPackageValue $Definition Id ''),[ref]$Id) -or $Id -eq [guid]::Empty){& $Add Id 'Package ID must be a GUID.'}
    $Revision=Get-RemoteOpsPackageValue $Definition Revision
    if($Revision -isnot [int] -and $Revision -isnot [long]){& $Add Revision 'Revision must be an integer.'}elseif($Revision -lt 1){& $Add Revision 'Revision must be positive.'}
    foreach($Field in @('Name','ApplicationKey')){if([string]::IsNullOrWhiteSpace([string](Get-RemoteOpsPackageValue $Definition $Field ''))){& $Add $Field 'This field is required.'}}
    foreach($Field in @('CollectLogs','DowngradeEnabled')){if((Get-RemoteOpsPackageValue $Definition $Field) -isnot [bool]){& $Add $Field 'Use a JSON boolean.'}}
    $EnabledCount=0
    foreach($Name in @('Install','Uninstall','Downgrade')){
        $Part=Get-RemoteOpsPackageValue $Definition $Name
        foreach($Field in @('PackagePath','PackageFile','SearchType','Application','RegistryKey','CheckMode')){
            if((Get-RemoteOpsPackageValue $Part $Field '') -isnot [string]){& $Add "$Name.$Field" 'Use a JSON string.'}
        }
        $Enabled=Get-RemoteOpsPackageValue $Part Enabled
        if($Enabled -isnot [bool]){& $Add "$Name.Enabled" 'Use a JSON boolean.';continue}
        if(-not $Enabled){continue};$EnabledCount++
        $Path=[string](Get-RemoteOpsPackageValue $Part PackagePath '')
        if($Path -notmatch '^\\\\[^\\/:*?"<>|\r\n]+\\[^\\/:*?"<>|\r\n]+(?:\\[^/:*?"<>|\r\n]*)?$' -or $Path -match '(^|\\)\.\.?($|\\)'){& $Add "$Name.PackagePath" 'Enter an absolute UNC package folder.'}
        $File=[string](Get-RemoteOpsPackageValue $Part PackageFile '')
        if($File -notmatch '(?i)^([^\\/:*?"<>|\r\n]+)\.(bat|cmd|ps1|vbs)$' -or $File -in @('.','..')){& $Add "$Name.PackageFile" 'Enter a .bat, .cmd, .ps1 or .vbs file name without a path.'}
        $Mode=[string](Get-RemoteOpsPackageValue $Part CheckMode '')
        if($Mode -notin @('Version controlled','Presence only','Trigger without checks')){& $Add "$Name.CheckMode" 'Choose a supported check mode.'}
        if((Get-RemoteOpsPackageValue $Part SearchType '') -notin @('DisplayName exact','DisplayName contains','ProductID')){& $Add "$Name.SearchType" 'Choose a supported application identity.'}
        $App=[string](Get-RemoteOpsPackageValue $Part Application '')
        if($Mode -ne 'Trigger without checks' -and [string]::IsNullOrWhiteSpace($App)){& $Add "$Name.Application" 'Application identity is required for checked execution.'}
        if($Name -eq 'Downgrade' -and $Mode -ne 'Version controlled'){& $Add 'Downgrade.CheckMode' 'Downgrade requires exact version verification.'}
        if($Name -eq 'Install' -and $Mode -eq 'Version controlled' -and [string]::IsNullOrWhiteSpace([string](Get-RemoteOpsPackageValue $Definition TargetVersion ''))){& $Add TargetVersion 'Target version is required for version-controlled installation.'}
    }
    if($EnabledCount -eq 0){& $Add Actions 'Enable at least one package action.'}
    if($Action -in @('Install','Uninstall') -and (Get-RemoteOpsPackageValue (Get-RemoteOpsPackageValue $Definition $Action) Enabled) -ne $true){& $Add "$Action.Enabled" 'This action is not configured.'}
    if($Action -eq 'Downgrade' -or (Get-RemoteOpsPackageValue $Definition DowngradeEnabled) -eq $true){
        if((Get-RemoteOpsPackageValue $Definition DowngradeEnabled) -ne $true){& $Add DowngradeEnabled 'Downgrade is not enabled.'}
        foreach($Name in @('Uninstall','Downgrade')){
            $Part=Get-RemoteOpsPackageValue $Definition $Name
            if((Get-RemoteOpsPackageValue $Part Enabled) -ne $true){& $Add "$Name.Enabled" 'Downgrade requires both actions.'}
            if([string]::IsNullOrWhiteSpace([string](Get-RemoteOpsPackageValue $Part Application '')) -or (Get-RemoteOpsPackageValue $Part CheckMode '') -eq 'Trigger without checks'){& $Add "$Name.Application" 'Downgrade requires application checks on both actions.'}
        }
        $Version=[string](Get-RemoteOpsPackageValue $Definition DowngradeVersion '')
        if($Version -notmatch '^[vV]?\d+(?:[._-]\d+)*$'){& $Add DowngradeVersion 'Downgrade requires a comparable numeric target version.'}
    }
    if((Get-RemoteOpsPackageValue (Get-RemoteOpsPackageValue $Definition Downgrade) Enabled $false) -ne (Get-RemoteOpsPackageValue $Definition DowngradeEnabled $false)){& $Add DowngradeEnabled 'Downgrade action and enable flag must agree.'}
    return [PSCustomObject]@{Valid=($Errors.Count -eq 0);Errors=@($Errors.ToArray())}
}
function Assert-RemoteOpsPackageDefinition {
    param($Definition,[string]$Action='')
    $Check=Test-RemoteOpsPackageDefinition $Definition $Action
    if(-not $Check.Valid){throw (($Check.Errors|ForEach-Object{$_.Field+': '+$_.Message}) -join "`r`n")}
}
function Get-RemoteOpsPackageRecordPath {
    param([string]$Root,[string]$Id)
    $Guid=[guid]::Empty
    if(-not[guid]::TryParse($Id,[ref]$Guid) -or $Guid -eq [guid]::Empty){throw 'Package ID must be a GUID.'}
    return Join-Path ([IO.Path]::GetFullPath($Root)) ($Guid.ToString('D')+'.json')
}
function Write-RemoteOpsAtomicJson {
    param([string]$Path,$Value,[int]$Depth=12)
    $Parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $Parent)){New-Item -ItemType Directory -Path $Parent -Force|Out-Null}
    $Temp=Join-Path $Parent ('.'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::WriteAllText($Temp,(ConvertTo-Json -InputObject $Value -Depth $Depth),[Text.UTF8Encoding]::new($true))
        if([IO.File]::Exists($Path)){[IO.File]::Replace($Temp,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($Temp,$Path)}
    }finally{if([IO.File]::Exists($Temp)){[IO.File]::Delete($Temp)}}
}
function Get-RemoteOpsPackageCatalog {
    param([string]$Root)
    $Packages=New-Object 'System.Collections.Generic.List[object]';$Errors=New-Object 'System.Collections.Generic.List[object]'
    if(Test-Path -LiteralPath $Root){foreach($File in @(Get-ChildItem -LiteralPath $Root -Filter '*.json' -File)){
        try{
            $Record=Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8|ConvertFrom-Json
            Assert-RemoteOpsPackageDefinition $Record
            $Expected=Get-RemoteOpsPackageRecordPath $Root ([string]$Record.Id)
            if(-not[string]::Equals($Expected,$File.FullName,[StringComparison]::OrdinalIgnoreCase)){throw 'Record ID does not match its file name.'}
            $Packages.Add((Copy-RemoteOpsPackageDefinition $Record))
        }catch{$Errors.Add([PSCustomObject]@{Path=$File.FullName;Message=$_.Exception.Message})}
    }}
    return [PSCustomObject]@{Packages=@($Packages.ToArray()|Sort-Object Name,TargetVersion);Errors=@($Errors.ToArray())}
}
function Save-RemoteOpsPackageDefinition {
    param([string]$Root,$Definition,[int]$ExpectedRevision=0)
    Assert-RemoteOpsPackageDefinition $Definition
    $Path=Get-RemoteOpsPackageRecordPath $Root ([string]$Definition.Id)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force|Out-Null
    $Lock=$null
    try{
        $Lock=[IO.File]::Open($Path+'.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $Copy=Copy-RemoteOpsPackageDefinition $Definition
        if(Test-Path -LiteralPath $Path){
            $Existing=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
            Assert-RemoteOpsPackageDefinition $Existing
            if($ExpectedRevision -ne [int]$Existing.Revision){throw 'Package changed since it was opened. Reload before saving.'}
            $Copy.Revision=[int]$Existing.Revision+1;$Copy.CreatedAt=$Existing.CreatedAt
        }else{if($ExpectedRevision -ne 0){throw 'Package was removed. Reload before saving.'};$Copy.Revision=1}
        $Copy.Id=([guid]$Copy.Id).ToString('D');$Copy.UpdatedAt=(Get-Date).ToString('o')
        Write-RemoteOpsAtomicJson $Path $Copy
        return $Copy
    }finally{if($null -ne $Lock){$Lock.Dispose()}}
}
function Remove-RemoteOpsPackageDefinition {
    param([string]$Root,[string]$Id,[int]$ExpectedRevision)
    $Path=Get-RemoteOpsPackageRecordPath $Root $Id
    $Lock=$null
    try{
        $Lock=[IO.File]::Open($Path+'.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $Record=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
        if([int]$Record.Revision -ne $ExpectedRevision){throw 'Package changed. Reload before deleting.'}
        Remove-Item -LiteralPath $Path -Force
    }finally{if($null -ne $Lock){$Lock.Dispose()}}
}
function Export-RemoteOpsPackageDefinitions {
    param([object[]]$Definitions,[string]$Path)
    $Rows=@(foreach($Record in $Definitions){Assert-RemoteOpsPackageDefinition $Record;Copy-RemoteOpsPackageDefinition $Record})
    Write-RemoteOpsAtomicJson $Path ([PSCustomObject]@{Schema='RemoteOps.PackageExport/2';Packages=$Rows})
}
function Get-RemoteOpsPackageImportPreview {
    param([string]$Root,[string]$Path)
    $Data=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    if((Get-RemoteOpsPackageValue $Data Schema '') -notin @('RemoteOps.PackageExport/1','RemoteOps.PackageExport/2')){throw 'Unsupported package export schema.'}
    $Rows=@(Get-RemoteOpsPackageValue $Data Packages @());$Seen=@{}
    foreach($Record in $Rows){Assert-RemoteOpsPackageDefinition $Record;$Key=([guid]$Record.Id).ToString('D');if($Seen.ContainsKey($Key)){throw 'Duplicate package IDs in import.'};$Seen[$Key]=$true}
    $Conflicts=@($Rows|Where-Object{Test-Path -LiteralPath (Get-RemoteOpsPackageRecordPath $Root ([string]$_.Id))})
    return [PSCustomObject]@{Packages=$Rows;Conflicts=$Conflicts}
}
function Import-RemoteOpsPackageDefinitions {
    param([string]$Root,[string]$Path,[ValidateSet('Skip','Copy','Replace')][string]$ConflictPolicy='Skip')
    $Preview=Get-RemoteOpsPackageImportPreview $Root $Path;$Rows=$Preview.Packages
    $Imported=New-Object 'System.Collections.Generic.List[object]';$Conflicts=New-Object 'System.Collections.Generic.List[object]';$Errors=New-Object 'System.Collections.Generic.List[object]'
    foreach($Record in $Rows){try{
        $Copy=Copy-RemoteOpsPackageDefinition $Record;$RecordPath=Get-RemoteOpsPackageRecordPath $Root $Copy.Id;$Revision=0
        if(Test-Path -LiteralPath $RecordPath){
            $Conflicts.Add([PSCustomObject]@{Id=$Copy.Id;Name=$Copy.Name})
            if($ConflictPolicy -eq 'Skip'){continue}
            if($ConflictPolicy -eq 'Copy'){$Copy=Copy-RemoteOpsPackageDefinition $Copy -NewIdentity}else{
                $Existing=Get-Content -LiteralPath $RecordPath -Raw -Encoding UTF8|ConvertFrom-Json;Assert-RemoteOpsPackageDefinition $Existing;$Revision=[int]$Existing.Revision
            }
        }
        $Imported.Add((Save-RemoteOpsPackageDefinition $Root $Copy $Revision))
    }catch{$Errors.Add([PSCustomObject]@{Id=[string]$Record.Id;Message=$_.Exception.Message})}}
    return [PSCustomObject]@{Imported=@($Imported.ToArray());Conflicts=@($Conflicts.ToArray());Errors=@($Errors.ToArray())}
}
