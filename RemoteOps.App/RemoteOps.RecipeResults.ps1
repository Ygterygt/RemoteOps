. (Join-Path $PSScriptRoot 'RemoteOps.Preview.ps1')
. (Join-Path $PSScriptRoot 'RemoteOps.Conditions.ps1')
function Test-RemoteOpsConditionEvidence {
 param($Row,$Check)
 try{
  foreach($Field in @('Kind','Path','Name','Operator','ExpectedType','Expected')){
   $Value=Get-RemoteOpsPreviewValue $Row $Field $null
   if($Value -isnot [string] -or $Value -cne $Check.$Field){return $false}
  }
  foreach($Field in @('ValueType','Value','State','Startup','Observed','ErrorDetail')){if((Get-RemoteOpsPreviewValue $Row $Field $null) -isnot [string]){return $false}}
  if((Get-RemoteOpsPreviewValue $Row Exists $null) -isnot [bool] -or (Get-RemoteOpsPreviewValue $Row Matched $null) -isnot [bool]){return $false}
  $Evidence=$Row
  $Probe={param($Check,$ComputerName) [pscustomobject]@{Exists=$Evidence.Exists;ValueType=$Evidence.ValueType;Value=$Evidence.Value;State=$Evidence.State;Startup=$Evidence.Startup;Detail=$Evidence.ErrorDetail}}.GetNewClosure()
  $Single=[pscustomobject]@{Match='All';OnFalse='Skip';Checks=@($Check)}
  $Verified=Invoke-RemoteOpsConditionChecks $Single ([string]$Row.ComputerName) ([string]$Row.OperationID) $Probe
  return (-not $Verified.Error -and $Verified.Matched -eq $Row.Matched -and $Verified.Rows[0].Observed -ceq $Row.Observed)
 }catch{return $false}
}
function Get-RemoteOpsRecipeStepDecision {
 param([string]$Operation,$Values,[object[]]$Rows,[object[]]$Outcomes=@())
 if($Operation -ceq 'RecipeCondition'){
  Assert-RemoteOpsConditionValues $Values
  $Valid=$Rows.Count -eq @($Values.Checks).Count
  $Indexes=@{}
  foreach($Row in $Rows){
   $Index=Get-RemoteOpsPreviewValue $Row CheckIndex 0
   if((Get-RemoteOpsPreviewValue $Row Status '') -cne 'Success' -or $Index -isnot [int] -or $Index -lt 1 -or $Index -gt @($Values.Checks).Count -or $Indexes.ContainsKey($Index)){$Valid=$false}
   elseif(-not (Test-RemoteOpsConditionEvidence $Row $Values.Checks[$Index-1])){$Valid=$false}
   $Indexes[$Index]=$true
  }
  if(-not $Valid){return [pscustomobject]@{Decision='Stop';Outcome='Error';Reason='Koşul kontrol edilemedi; bu hedef durduruldu.';ConditionMatched=$false}}
  $TrueCount=@($Rows|Where-Object Matched -eq $true).Count
  $Matched=if($Values.Match -ceq 'All'){$TrueCount -eq $Rows.Count}else{$TrueCount -gt 0}
  $Stop=-not $Matched -and $Values.OnFalse -ceq 'Stop'
  return [pscustomobject]@{Decision=$(if($Stop){'Stop'}else{'Continue'});Outcome=$(if($Stop){'Skipped'}else{'Completed'});Reason=$(if($Matched){'Koşul sağlandı.'}elseif($Stop){'Koşul sağlanmadı; bu hedefin reçetesi durduruldu.'}else{'Koşul sağlanmadı; bağlı adımlar atlanacak.'});ConditionMatched=[bool]$Matched}
 }
 $Outcome='Error';$Reason='Adım sonucu doğrulanamadı.';$Continue=$false
 $Statuses=@($Rows|ForEach-Object{[string](Get-RemoteOpsPreviewValue $_ Status (Get-RemoteOpsPreviewValue $_ Durum ''))})
 $All=@($Statuses)+@($Outcomes|ForEach-Object{Get-RemoteOpsPreviewValue $_ Outcome ''})
 foreach($Special in @('Indeterminate','RebootRequired','Cancelled','Unreachable')){if($All -contains $Special){return [pscustomobject]@{Decision='Stop';Outcome=$Special;Reason='Adım durdu: '+$Special}}}
 if(@($Rows|Where-Object{(Get-RemoteOpsPreviewValue $_ RebootRequired $false) -in @($true,'True') -or (Get-RemoteOpsPreviewValue $_ ExitCode '') -in @('3010','1641',3010,1641)}).Count){return [pscustomobject]@{Decision='Stop';Outcome='RebootRequired';Reason='Yeniden başlatma gerekiyor; zincir durdu.'}}
 $Fatal=@($All|Where-Object{$_ -in @('Failed','Error','Erisilemedi','NoData','NotRun','BackupFailed','Blocked')})
 if($Rows.Count -gt 0 -and -not $Fatal.Count){
  $Invalid=@(foreach($R in $Rows){
   $Status=[string](Get-RemoteOpsPreviewValue $R Status (Get-RemoteOpsPreviewValue $R Durum ''))
   $Valid=switch($Operation){
    ServiceList {$Status -in @('Success','NotFound')}
    RegistryRead {$Status -eq 'Success' -and [string](Get-RemoteOpsPreviewValue $R ReturnValue '') -eq '0' -or $Status -eq 'NotFound' -and [string](Get-RemoteOpsPreviewValue $R ReturnValue '') -eq '2'}
    {$_ -in @('ServiceControl','ServiceStartup')} {$Status -eq 'Success'}
    {$_ -in @('RegistryEdit','RegistryDelete')} {$Status -eq 'Success' -and [string](Get-RemoteOpsPreviewValue $R ReturnValue '') -eq '0'}
    FileCompare {$Status -eq 'Esit' -and [string](Get-RemoteOpsPreviewValue $R HashEsit '') -eq 'True' -and [string](Get-RemoteOpsPreviewValue $R SizeEsit '') -eq 'True' -and [string](Get-RemoteOpsPreviewValue $R ModifiedEsit '') -eq 'True'}
    FilePush {$Status -eq 'Success' -and [string](Get-RemoteOpsPreviewValue $R AtlananAdet '') -eq '0'}
    FileDelete {$Status -eq 'Success' -and (Get-RemoteOpsPreviewValue $R BackupDurumu '') -eq 'Verified' -and (Get-RemoteOpsPreviewValue $R BackupDogrulandi '') -eq 'Evet' -and (Get-RemoteOpsPreviewValue $R KaynakStabil '') -eq 'Evet' -and (Get-RemoteOpsPreviewValue $R SilmeSonKontrol '') -eq 'Verified'}
    PackageDeployment {$Status -in @('Success','SuccessRebootRequired','Skipped','Var','Yok')}
    default {$false}
   };if(-not $Valid){$R}
  })
  $Continue=$Invalid.Count -eq 0
  if($Operation -eq 'PackageDeployment'){
   $Continue=$Continue -and $Outcomes.Count -eq 1
   if($Continue){$O=$Outcomes[0];$Continue=$O.Outcome -eq 'Success' -or ($O.Outcome -eq 'Skipped' -and (Get-RemoteOpsPreviewValue $O DecisionCode '') -in @('AlreadyAbsent','AlreadyPresent','AlreadyAtOrAboveTarget','AlreadyAtTarget'))}
  }
 }
 if($Continue){$Outcome='Completed';$Reason='Adımın beklenen sonucu doğrulandı.'}elseif($All -contains 'Erisilemedi'){$Outcome='Unreachable'}
 [pscustomobject]@{Decision=$(if($Continue){'Continue'}else{'Stop'});Outcome=$Outcome;Reason=$Reason}
}
