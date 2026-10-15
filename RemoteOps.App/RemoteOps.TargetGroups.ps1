# Personal target groups. No remote access or credentials.
function ConvertTo-RemoteOpsTargets {
    param([string]$Text)
    if($Text -cmatch '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'){throw 'Hedef listesi kontrol karakteri içeriyor.'}
    $Seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($Name in ($Text -split '[\s,;]+')){
        if(-not $Name){continue}
        if($Name.Length -gt 253 -or $Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$|^[A-Za-z0-9]$'){throw ('Geçersiz hedef: '+$Name)}
        foreach($Label in $Name.Split('.')){if($Label.Length -lt 1 -or $Label.Length -gt 63 -or $Label.StartsWith('-') -or $Label.EndsWith('-')){throw ('Geçersiz hedef: '+$Name)}}
        if($Name -cmatch '^[0-9.]+$' -and $Name.Contains('.')){
            $Parts=$Name.Split('.');if($Parts.Count -ne 4){throw ('Geçersiz IPv4: '+$Name)}
            foreach($Part in $Parts){if($Part.Length -gt 3 -or [int]$Part -gt 255 -or ($Part.Length -gt 1 -and $Part.StartsWith('0'))){throw ('Geçersiz IPv4: '+$Name)}}
        }
        if($Seen.Add($Name)){$Name}
    }
}
function Assert-RemoteOpsTargetGroup {
    param($Group)
    if($null -eq $Group){throw 'Hedef grubu eksik.'}
    $Allowed=@('Schema','Id','Revision','Name','Description','Targets','CreatedAt','UpdatedAt')
    foreach($Property in $Group.PSObject.Properties){if($Property.Name -notin $Allowed){throw ('Desteklenmeyen grup alanı: '+$Property.Name)}}
    foreach($Key in $Allowed){if($null -eq $Group.PSObject.Properties[$Key]){throw ('Eksik grup alanı: '+$Key)}}
    foreach($Key in @('Schema','Id','Name','Description','CreatedAt','UpdatedAt')){if($Group.$Key -isnot [string]){throw ('Metin alanı bekleniyor: '+$Key)}}
    if($Group.Schema -cne 'RemoteOps.TargetGroup/1'){throw 'Desteklenmeyen hedef grubu şeması.'}
    $Guid=[guid]::Empty;if(-not [guid]::TryParseExact($Group.Id,'D',[ref]$Guid) -or $Guid -eq [guid]::Empty){throw 'Geçersiz grup kimliği.'}
    if($Group.Revision -isnot [int] -and $Group.Revision -isnot [long]){throw 'Geçersiz grup revizyonu.'}
    if($Group.Revision -lt 0 -or $Group.Revision -ge [int]::MaxValue){throw 'Grup revizyonu sınır dışında.'}
    if([string]::IsNullOrWhiteSpace($Group.Name) -or $Group.Name.Length -gt 120 -or $Group.Description.Length -gt 2000){throw 'Grup adı boş/çok uzun veya açıklama çok uzun.'}
    if($Group.Targets -isnot [array] -or $Group.Targets.Count -eq 0){throw 'En az bir hedef içeren dizi gerekir.'}
    foreach($Target in $Group.Targets){if($Target -isnot [string] -or @(ConvertTo-RemoteOpsTargets $Target).Count -ne 1){throw 'Geçersiz hedef dizisi.'}}
    $Normalized=@(ConvertTo-RemoteOpsTargets ($Group.Targets -join "`n"))
    if($Normalized.Count -ne $Group.Targets.Count){throw 'Grup yinelenen hedef içeriyor.'}
}
function New-RemoteOpsTargetGroup {
    param([string]$Name,[string]$Description,[string]$TargetsText)
    $Now=(Get-Date).ToString('o')
    $Group=[pscustomobject]@{Schema='RemoteOps.TargetGroup/1';Id=[guid]::NewGuid().ToString('D');Revision=0;Name=$Name.Trim();Description=$Description;Targets=@(ConvertTo-RemoteOpsTargets $TargetsText);CreatedAt=$Now;UpdatedAt=$Now}
    Assert-RemoteOpsTargetGroup $Group;return $Group
}
function Resolve-RemoteOpsTargetGroupPath {
    param([string]$Root,[string]$Id='')
    $FullRoot=[IO.Path]::GetFullPath($Root)
    $Path=$FullRoot
    if($Id){$Guid=[guid]::Empty;if(-not [guid]::TryParseExact($Id,'D',[ref]$Guid) -or $Guid -eq [guid]::Empty){throw 'Geçersiz grup kimliği.'};$Path=Join-Path $FullRoot ($Guid.ToString('D')+'.json')}
    $Current=$Path
    while($Current){
        if(Test-Path -LiteralPath $Current){if(((Get-Item -LiteralPath $Current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Hedef grubu yolu bağlantı/junction içeremez.'}}
        $Next=[IO.Path]::GetDirectoryName($Current);if($Next -eq $Current){break};$Current=$Next
    }
    return $Path
}
function Get-RemoteOpsTargetGroupCatalog {
    param([string]$Root)
    $Groups=New-Object System.Collections.ArrayList;$Errors=New-Object System.Collections.ArrayList
    try{
        $Path=Resolve-RemoteOpsTargetGroupPath $Root
        if(Test-Path -LiteralPath $Path){foreach($File in @(Get-ChildItem -LiteralPath $Path -Filter '*.json' -File)){
            try{
                $Record=Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8|ConvertFrom-Json
                Assert-RemoteOpsTargetGroup $Record
                $Expected=Resolve-RemoteOpsTargetGroupPath $Root $Record.Id
                if(-not $Expected.Equals($File.FullName,[StringComparison]::OrdinalIgnoreCase)){throw 'Grup kimliği dosya adıyla uyuşmuyor.'}
                if($Record.Revision -lt 1){throw 'Kaydedilmiş grup revizyonu geçersiz.'}
                [void]$Groups.Add($Record)
            }catch{[void]$Errors.Add([pscustomobject]@{Path=$File.FullName;Message=$_.Exception.Message})}
        }}
    }catch{[void]$Errors.Add([pscustomobject]@{Path=$Root;Message=$_.Exception.Message})}
    return [pscustomobject]@{Groups=@($Groups|Sort-Object Name,Id);Errors=@($Errors)}
}
function Save-RemoteOpsTargetGroup {
    param([string]$Root,$Group,[int]$ExpectedRevision=0)
    Assert-RemoteOpsTargetGroup $Group
    $Path=Resolve-RemoteOpsTargetGroupPath $Root $Group.Id
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Path)) -Force|Out-Null
    $LockPath=$Path+'.lock';if(Test-Path -LiteralPath $LockPath){if(((Get-Item -LiteralPath $LockPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Geçersiz kilit yolu.'}}
    $Lock=[IO.File]::Open($LockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        [void](Resolve-RemoteOpsTargetGroupPath $Root $Group.Id)
        $Copy=$Group|ConvertTo-Json -Depth 8|ConvertFrom-Json
        if(Test-Path -LiteralPath $Path){
            $Existing=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json;Assert-RemoteOpsTargetGroup $Existing
            if($Existing.Id -ne $Group.Id -or $ExpectedRevision -ne $Existing.Revision){throw 'Grup değişti. Yenileyip yeniden düzenleyin.'}
            $Copy.Revision=[int]$Existing.Revision+1;$Copy.CreatedAt=$Existing.CreatedAt
        }else{if($ExpectedRevision -ne 0){throw 'Grup silinmiş. Yeni kayıt için yeniden oluşturun.'};$Copy.Revision=1}
        $Copy.Name=$Copy.Name.Trim();$Copy.UpdatedAt=(Get-Date).ToString('o');Assert-RemoteOpsTargetGroup $Copy
        Write-RemoteOpsAtomicJson $Path $Copy;return $Copy
    }finally{$Lock.Dispose()}
}
function Remove-RemoteOpsTargetGroup {
    param([string]$Root,[string]$Id,[int]$ExpectedRevision)
    $Path=Resolve-RemoteOpsTargetGroupPath $Root $Id
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Grup bulunamadı.'}
    $LockPath=$Path+'.lock';if(Test-Path -LiteralPath $LockPath){if(((Get-Item -LiteralPath $LockPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Geçersiz kilit yolu.'}}
    $Lock=[IO.File]::Open($LockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        [void](Resolve-RemoteOpsTargetGroupPath $Root $Id)
        $Existing=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json;Assert-RemoteOpsTargetGroup $Existing
        if($Existing.Id -ne $Id -or $ExpectedRevision -ne $Existing.Revision){throw 'Grup değişti. Silmeden önce yenileyin.'}
        [IO.File]::Delete($Path)
    }finally{$Lock.Dispose()}
}
function Merge-RemoteOpsTargetGroup {
    param([string]$CurrentText,[string[]]$GroupTargets,[ValidateSet('Add','Replace')][string]$Mode)
    $Text=if($Mode -eq 'Add'){$CurrentText+"`n"+($GroupTargets -join "`n")}else{$GroupTargets -join "`n"}
    return @(ConvertTo-RemoteOpsTargets $Text)
}
