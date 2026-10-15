. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\RegistryPaths.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\RegistryValues.ps1')

function Get-RemoteOpsManifestField {
    param($Entry,[string]$Name,[string]$Default='')
    if($Entry.PSObject.Properties[$Name]){return [string]$Entry.$Name}
    return $Default
}

function Get-RemoteOpsRollbackChoices {
    param([Parameter(Mandatory=$true)][string]$BasePath,[Parameter(Mandatory=$true)][ValidateSet('RegistryRollback','ServiceTaskRollback')][string]$OperationName)
    $Folder=if($OperationName -eq 'RegistryRollback'){'RegistryRollback'}else{'ServiceTaskRollbacks'}
    foreach($File in @(Get-ChildItem -LiteralPath (Join-Path $BasePath $Folder) -Filter '*.csv' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending)){
        try{$Entries=@(Import-Csv -LiteralPath $File.FullName -Delimiter ';' -ErrorAction Stop)}catch{continue}
        $Details=@(foreach($Entry in $Entries){
            $Computer=Get-RemoteOpsManifestField $Entry 'ComputerName'
            if(-not $Computer){continue}
            if($OperationName -eq 'RegistryRollback'){
                if(-not $Entry.PSObject.Properties['RegistryKey'] -or -not $Entry.PSObject.Properties['ValueName'] -or -not $Entry.PSObject.Properties['OldExists']){continue}
                try{$Path=Get-RemoteOpsRegistryManifestPath $Entry}catch{continue}
                $Old=if([string]$Entry.OldExists -eq 'True'){ConvertTo-Json -InputObject ([string](Get-RemoteOpsManifestField $Entry 'OldValue')) -Compress}else{'[absent]'}
                $New=if((Get-RemoteOpsManifestField $Entry 'Action') -eq 'Delete'){'[absent]'}elseif($Entry.PSObject.Properties['NewValue']){ConvertTo-Json -InputObject ([string]$Entry.NewValue) -Compress}else{'[unknown]'}
                $OldType=if([string]$Entry.OldExists -eq 'True'){Get-RemoteOpsManifestField $Entry 'OldType' 'REG_SZ'}else{'absent'}
                if($OldType -in @('REG_DWORD','REG_QWORD','REG_MULTI_SZ')){$Old=[string]$Entry.OldValue}
                $NewType=if((Get-RemoteOpsManifestField $Entry 'Action') -eq 'Delete'){'absent'}else{Get-RemoteOpsManifestField $Entry 'NewType' 'REG_SZ'}
                if($NewType -in @('REG_DWORD','REG_QWORD','REG_MULTI_SZ')){$New=[string]$Entry.NewValue}
                $TypeHint=' | type: '+$NewType+' -> '+$OldType
                $Outcome=Get-RemoteOpsManifestField $Entry 'ReturnValue'
                $OutcomeHint=if($Outcome -and $Outcome -ne '0'){' | recorded result='+$Outcome}else{''}
                '{0}: {1} [{2}] | {3} -> {4}{5}' -f $Computer,$Path.FullPath,$Entry.ValueName,$New,$Old,($TypeHint+$OutcomeHint)
            }else{
                $Type=Get-RemoteOpsManifestField $Entry 'ObjectType'
                $Action=Get-RemoteOpsManifestField $Entry 'Action'
                $Name=Get-RemoteOpsManifestField $Entry 'ObjectName'
                if($Type -eq 'Service' -and $Action -eq 'StartupType'){
                    '{0}: Service {1} | {2} -> {3}' -f $Computer,$Name,(Get-RemoteOpsManifestField $Entry 'NewStartMode' '[unknown]'),(Get-RemoteOpsManifestField $Entry 'OldStartMode')
                }elseif($Type -eq 'Service' -and $Action -eq 'StartStop'){
                    '{0}: Service {1} | {2} -> {3}' -f $Computer,$Name,(Get-RemoteOpsManifestField $Entry 'NewState' '[recorded change]'),(Get-RemoteOpsManifestField $Entry 'OldState')
                }elseif($Type -eq 'ScheduledTask' -and $Action -eq 'Delete'){
                    '{0}: Task {1}{2} | [absent] -> restore XML backup' -f $Computer,(Get-RemoteOpsManifestField $Entry 'TaskPath'),$Name
                }elseif($Type -eq 'ScheduledTask' -and $Action -eq 'EnableDisable'){
                    '{0}: Task {1}{2} | Enabled={3} -> Enabled={4}' -f $Computer,(Get-RemoteOpsManifestField $Entry 'TaskPath'),$Name,(Get-RemoteOpsManifestField $Entry 'NewEnabled' '[recorded change]'),(Get-RemoteOpsManifestField $Entry 'OldEnabled')
                }
            }
        })
        if($Details.Count -eq 0){continue}
        [pscustomobject]@{Id=$File.FullName;Display=('{0:dd.MM.yyyy HH:mm:ss} | {1} | {2}' -f $File.LastWriteTime,($Details -join ' ; '),$File.Name)}
    }
}

function Get-RemoteOpsBackupChoices {
    param([Parameter(Mandatory=$true)][string]$BasePath)
    $Runs=@(Get-ChildItem -LiteralPath (Join-Path $BasePath 'DeleteBackups') -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach($Run in $Runs){
        $Manifest=Join-Path $Run.FullName 'manifest.csv'
        if(-not(Test-Path -LiteralPath $Manifest -PathType Leaf)){continue}
        try{$Entries=@(Import-Csv -LiteralPath $Manifest -Delimiter ';' -ErrorAction Stop)}catch{continue}
        $Details=@(foreach($Entry in $Entries){
            if($Entry.PSObject.Properties['ComputerName'] -and $Entry.PSObject.Properties['OriginalPath']){
                '{0}: {1}' -f $Entry.ComputerName,$Entry.OriginalPath
            }
        }) | Select-Object -Unique
        if(@($Details).Count -eq 0){continue}
        [pscustomobject]@{Id=$Run.Name;Display=('{0:dd.MM.yyyy HH:mm:ss} | {1} | {2}' -f $Run.LastWriteTime,($Details -join ' ; '),$Run.Name)}
    }
}
