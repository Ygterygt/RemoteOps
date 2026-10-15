# Registry values are stored as exact text plus an explicit type in CSV manifests.
# Integers use decimal strings, MULTI_SZ uses a JSON string array, strings stay raw.
function Get-RemoteOpsRegistryTypeInfo {
    param([Parameter(Mandatory=$true)][string]$Type)
    switch($Type){
        'REG_SZ' {[pscustomobject]@{Code=1;Name='REG_SZ';Getter='GetStringValue';Setter='SetStringValue';Argument='sValue'}}
        'REG_EXPAND_SZ' {[pscustomobject]@{Code=2;Name='REG_EXPAND_SZ';Getter='';Setter='SetExpandedStringValue';Argument='sValue'}}
        'REG_DWORD' {[pscustomobject]@{Code=4;Name='REG_DWORD';Getter='GetDWORDValue';Setter='SetDWORDValue';Argument='uValue'}}
        'REG_MULTI_SZ' {[pscustomobject]@{Code=7;Name='REG_MULTI_SZ';Getter='GetMultiStringValue';Setter='SetMultiStringValue';Argument='sValue'}}
        'REG_QWORD' {[pscustomobject]@{Code=11;Name='REG_QWORD';Getter='GetQWORDValue';Setter='SetQWORDValue';Argument='uValue'}}
        default {throw "Unsupported registry type: $Type"}
    }
}

function ConvertTo-RemoteOpsRegistryData {
    param([Parameter(Mandatory=$true)][string]$Type,[AllowEmptyString()][string]$Text)
    $Info=Get-RemoteOpsRegistryTypeInfo $Type
    if($Info.Name -in @('REG_DWORD','REG_QWORD')){
        $InputText=$Text.Trim();$Number=[uint64]0
        if($InputText -match '^0[xX][0-9a-fA-F]+$'){
            try{$Number=[Convert]::ToUInt64($InputText.Substring(2),16)}catch{throw 'Registry integer is out of range.'}
        }elseif($InputText -match '^[0-9]+$' -and [uint64]::TryParse($InputText,[ref]$Number)){
        }else{throw 'Registry integer must be unsigned decimal or 0x hexadecimal.'}
        if($Info.Name -eq 'REG_DWORD' -and $Number -gt [uint32]::MaxValue){throw 'DWORD must be between 0 and 4294967295.'}
        return $Number.ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    if($Info.Name -eq 'REG_MULTI_SZ'){
        if($Text.Trim() -notmatch '(?s)^\[.*\]$'){throw 'REG_MULTI_SZ requires a JSON string array, for example ["one","two"].'}
        $Parsed=ConvertFrom-Json -InputObject $Text -ErrorAction Stop
        $Values=@($Parsed)
        foreach($Value in $Values){if($Value -isnot [string] -or $Value.Contains([char]0)){throw 'REG_MULTI_SZ items must be strings without NUL characters.'}}
        return ConvertTo-Json -InputObject ([string[]]$Values) -Compress
    }
    if($Text.Contains([char]0)){throw 'Registry strings cannot contain NUL characters.'}
    return $Text
}

function Get-RemoteOpsRawExpandString {
    param($Session,[uint32]$Hive,[string]$RegistryKey,[string]$ValueName)
    # StdRegProv.GetExpandedStringValue expands variables and cannot be a lossless backup.
    $Base=$null;$Key=$null
    try{
        $NativeHive=[Microsoft.Win32.RegistryHive]([int][long]($Hive-4294967296))
        $Computer=[string]$Session.ComputerName
        if($Computer -in @('.','localhost',$env:COMPUTERNAME)){$Base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($NativeHive,[Microsoft.Win32.RegistryView]::Default)}else{$Base=[Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($NativeHive,$Computer)}
        $Key=$Base.OpenSubKey($RegistryKey,$false)
        if($null -eq $Key -or $Key.GetValueKind($ValueName) -ne [Microsoft.Win32.RegistryValueKind]::ExpandString){throw 'REG_EXPAND_SZ value missing or type changed.'}
        $Raw=$Key.GetValue($ValueName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if($null -eq $Raw){throw 'REG_EXPAND_SZ value disappeared during backup.'}
        return [string]$Raw
    }catch{throw ('Raw REG_EXPAND_SZ read failed; Remote Registry access is required. Nothing was changed. '+$_.Exception.Message)}
    finally{if($null -ne $Key){$Key.Dispose()};if($null -ne $Base){$Base.Dispose()}}
}

function Get-RemoteOpsRegistryValue {
    param($Session,[uint32]$Hive=2147483650,[string]$RegistryKey,[string]$ValueName)
    $Args=@{hDefKey=$Hive;sSubKeyName=$RegistryKey}
    $Enum=Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName EnumValues -Arguments $Args -ErrorAction Stop
    $Type='';$Value='';$Code=[uint32]$Enum.ReturnValue
    if($Code -eq 0){
        $Names=@($Enum.sNames);$Types=@($Enum.Types);$Index=-1
        for($i=0;$i -lt $Names.Count;$i++){if([string]::Equals([string]$Names[$i],$ValueName,[StringComparison]::OrdinalIgnoreCase)){$Index=$i;break}}
        if($Index -lt 0){$Code=2}else{
            $Type=switch([int]$Types[$Index]){1{'REG_SZ'}2{'REG_EXPAND_SZ'}4{'REG_DWORD'}7{'REG_MULTI_SZ'}11{'REG_QWORD'}default{'UNSUPPORTED'}}
            if($Type -eq 'UNSUPPORTED'){$Code=50}else{
                $Info=Get-RemoteOpsRegistryTypeInfo $Type
                if($Type -eq 'REG_EXPAND_SZ'){$Value=Get-RemoteOpsRawExpandString -Session $Session -Hive $Hive -RegistryKey $RegistryKey -ValueName $ValueName}
                else{
                    $Args.sValueName=$ValueName
                    $Result=Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName $Info.Getter -Arguments $Args -ErrorAction Stop
                    $Code=[uint32]$Result.ReturnValue
                    if($Code -eq 0){
                        $Value=if($Type -eq 'REG_MULTI_SZ'){$Array=[string[]]@();if($null -ne $Result.sValue){$Array=[string[]]@($Result.sValue)};ConvertTo-Json -InputObject $Array -Compress}elseif($Type -eq 'REG_DWORD'){([uint32]$Result.uValue).ToString([Globalization.CultureInfo]::InvariantCulture)}elseif($Type -eq 'REG_QWORD'){([uint64]$Result.uValue).ToString([Globalization.CultureInfo]::InvariantCulture)}else{[string]$Result.sValue}
                    }
                }
            }
        }
    }
    [pscustomobject]@{Exists=($Code -eq 0);Value=$Value;Type=$Type;ReturnValue=$Code}
}

function Set-RemoteOpsRegistryValue {
    param($Session,[uint32]$Hive=2147483650,[string]$RegistryKey,[string]$ValueName,[string]$Type,[AllowEmptyString()][string]$Text)
    $Info=Get-RemoteOpsRegistryTypeInfo $Type
    $Canonical=ConvertTo-RemoteOpsRegistryData -Type $Type -Text $Text
    $Args=@{hDefKey=$Hive;sSubKeyName=$RegistryKey;sValueName=$ValueName}
    $Args[$Info.Argument]=switch($Info.Name){
        'REG_DWORD' {[uint32]::Parse($Canonical,[Globalization.CultureInfo]::InvariantCulture)}
        'REG_QWORD' {[uint64]::Parse($Canonical,[Globalization.CultureInfo]::InvariantCulture)}
        'REG_MULTI_SZ' {$Parsed=ConvertFrom-Json -InputObject $Canonical;,[string[]]@($Parsed)}
        default {$Canonical}
    }
    Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName $Info.Setter -Arguments $Args -ErrorAction Stop
}

function Restore-RemoteOpsRegistryEntry {
    param($Session,$Entry)
    $Path=Get-RemoteOpsRegistryManifestPath $Entry
    if($Path.HiveName -eq 'HKEY_CURRENT_USER'){throw 'Rollback requires the recorded HKU SID path.'}
    if([string]$Entry.OldExists -eq 'True'){
        $Type=if($Entry.PSObject.Properties['OldType'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.OldType)){[string]$Entry.OldType}else{'REG_SZ'}
        return Set-RemoteOpsRegistryValue -Session $Session -Hive $Path.Hive -RegistryKey $Path.SubKey -ValueName $Entry.ValueName -Type $Type -Text ([string]$Entry.OldValue)
    }
    Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName DeleteValue -Arguments @{hDefKey=$Path.Hive;sSubKeyName=$Path.SubKey;sValueName=[string]$Entry.ValueName} -ErrorAction Stop
}
