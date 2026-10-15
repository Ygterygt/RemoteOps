# Shared by the UI, registry menu and runner. No remote calls during load.
function ConvertTo-RemoteOpsRegistryPath {
    param([Parameter(Mandatory=$true)][string]$RegistryKey)
    $Path=$RegistryKey.Trim().Replace('/','\') -replace '^(?i)(Microsoft\.PowerShell\.Core\\)?Registry::',''
    $HiveName='HKEY_LOCAL_MACHINE';$Hive=[uint32]2147483650
    if($Path -match '^(?i)(HKLM|HKEY_LOCAL_MACHINE|HKCU|HKEY_CURRENT_USER|HKU|HKEY_USERS|HKCR|HKEY_CLASSES_ROOT|HKCC|HKEY_CURRENT_CONFIG)(?::?\\|$)'){
        $Prefix=$Matches[1].ToUpperInvariant()
        $Path=$Path.Substring($Matches[0].Length)
        switch -Regex ($Prefix){
            '^(HKLM|HKEY_LOCAL_MACHINE)$' {$HiveName='HKEY_LOCAL_MACHINE';$Hive=[uint32]2147483650}
            '^(HKCU|HKEY_CURRENT_USER)$' {$HiveName='HKEY_CURRENT_USER';$Hive=[uint32]2147483649}
            '^(HKU|HKEY_USERS)$' {$HiveName='HKEY_USERS';$Hive=[uint32]2147483651}
            '^(HKCR|HKEY_CLASSES_ROOT)$' {$HiveName='HKEY_CLASSES_ROOT';$Hive=[uint32]2147483648}
            '^(HKCC|HKEY_CURRENT_CONFIG)$' {$HiveName='HKEY_CURRENT_CONFIG';$Hive=[uint32]2147483653}
        }
    }elseif($Path -match '^(?i)(HKEY_|HK[A-Z]+[:\\])' -or $Path.Contains(':')){throw 'Desteklenmeyen registry koku. HKLM, HKCU, HKU, HKCR veya HKCC kullanin.'}
    $Path=$Path.Trim('\')
    if([string]::IsNullOrWhiteSpace($Path) -or @($Path -split '\\'|Where-Object{$_ -in @('.','..','')}).Count -gt 0){throw 'Registry alt anahtar yolu gecersiz veya bos.'}
    [pscustomobject]@{Hive=$Hive;HiveName=$HiveName;SubKey=$Path;FullPath=($HiveName+'\'+$Path)}
}

function Resolve-RemoteOpsRegistryPath {
    param($Session,[Parameter(Mandatory=$true)][string]$RegistryKey)
    $Parsed=ConvertTo-RemoteOpsRegistryPath $RegistryKey
    if($Parsed.HiveName -ne 'HKEY_CURRENT_USER'){return $Parsed}
    $Accounts=@(foreach($Logon in @(Get-CimInstance -CimSession $Session -ClassName Win32_LogonSession -Filter 'LogonType=2 OR LogonType=10 OR LogonType=11' -ErrorAction Stop)){
        Get-CimAssociatedInstance -CimSession $Session -InputObject $Logon -Association Win32_LoggedOnUser -ResultClassName Win32_Account -ErrorAction Stop
    })
    $Sids=@($Accounts|ForEach-Object{[string]$_.SID}|Where-Object{$_ -and $_ -notin @('S-1-5-18','S-1-5-19','S-1-5-20')}|Select-Object -Unique)
    if($Sids.Count -ne 1){throw 'HKCU icin tek bir oturum acmis kullanici bulunamadi. Acik HKU\<SID> yolu kullanin.'}
    $Loaded=Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName EnumKey -Arguments @{hDefKey=[uint32]2147483651;sSubKeyName=$Sids[0]} -ErrorAction Stop
    if([uint32]$Loaded.ReturnValue -ne 0){throw 'HKCU kullanici hive erisimi basarisiz. HKU\<SID> yolunu ve izinleri kontrol edin.'}
    ConvertTo-RemoteOpsRegistryPath ('HKEY_USERS\'+$Sids[0]+'\'+$Parsed.SubKey)
}

function Get-RemoteOpsRegistryManifestPath {
    param([Parameter(Mandatory=$true)]$Entry)
    if($Entry.PSObject.Properties['RegistryPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.RegistryPath)){
        return ConvertTo-RemoteOpsRegistryPath ([string]$Entry.RegistryPath)
    }
    if($Entry.PSObject.Properties['RegistryHive'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.RegistryHive)){
        return ConvertTo-RemoteOpsRegistryPath ([string]$Entry.RegistryHive+'\'+[string]$Entry.RegistryKey)
    }
    ConvertTo-RemoteOpsRegistryPath ([string]$Entry.RegistryKey)
}
