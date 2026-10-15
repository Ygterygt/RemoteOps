# Read-only postconditions. Never reissues a mutation or changes a saved recipe.
. (Join-Path $PSScriptRoot 'RemoteOps.Preview.ps1')
. (Join-Path $PSScriptRoot 'RemoteOps.Conditions.ps1')
function Get-RemoteOpsVerificationLabel {
 param([string]$Code)
 switch -CaseSensitive ($Code) {
  Verified {'Doğrulandı'} Failed {'Beklenen sonuç oluşmadı'} Unknown {'Doğrulanamadı'}
  NotPerformed {'Yapılmadı'} NotRequired {'Okuma / kontrol adımı'}
  default {'Bu kayıtta otomatik doğrulama yok'}
 }
}
function Set-RemoteOpsPostVerification {
 [CmdletBinding()]
 param([string]$Operation,$Values,[object[]]$Rows,[string]$ComputerName,
 [scriptblock]$Probe={param($Check,$Computer) Read-RemoteOpsVerificationProbe $Check $Computer},
 [ValidateRange(0,30)][int]$TimeoutSeconds=30,$PushManifest=$null)
 if($Operation -notin @('ServiceControl','ServiceStartup','RegistryEdit','RegistryDelete','FilePush')){return}
 $Accepted=$Rows.Count -gt 0
 foreach($Row in $Rows){
  if(-not $Row.PSObject.Properties['Operation']){Add-Member -InputObject $Row -NotePropertyName Operation -NotePropertyValue $Operation}
  if(-not $Row.PSObject.Properties['StepName']){
   $Name=switch($Operation){
    ServiceControl {$(switch([string]$Values.Action){Start{'Servisi başlat'}Stop{'Servisi durdur'}Restart{'Servisi yeniden başlat'}})+' · '+$Values.ServiceName}
    ServiceStartup {'Servis başlangıcını değiştir · '+$Values.ServiceName}
    RegistryEdit {'Registry değerini değiştir · '+$Values.ValueName}
    RegistryDelete {'Registry değerini sil · '+$Values.ValueName}
    FilePush {'Dosya gönder · '+$Values.Path}
   }
   Add-Member -InputObject $Row -NotePropertyName StepName -NotePropertyValue $Name
  }
  $Status=[string](Get-RemoteOpsPreviewValue $Row Status (Get-RemoteOpsPreviewValue $Row Durum ''))
  if($Status -cne 'Success'){$Accepted=$false}
  if($Operation -in @('RegistryEdit','RegistryDelete') -and [string](Get-RemoteOpsPreviewValue $Row ReturnValue '') -cne '0'){$Accepted=$false}
  if($Operation -eq 'FilePush' -and [string](Get-RemoteOpsPreviewValue $Row AtlananAdet '') -cne '0'){$Accepted=$false}
  foreach($Pair in @{CommandStatus=$Status;VerificationStatus='NotPerformed';VerificationExpected='';VerificationObserved='';VerificationDetail='Komut tamamlanmadı veya öğeler atlandı; sonuç doğrulaması yapılmadı.';VerifiedAt=''}.GetEnumerator()){
   Add-Member -InputObject $Row -NotePropertyName $Pair.Key -NotePropertyValue $Pair.Value -Force
  }
 }
 if(-not $Accepted){return}
 $Code='Unknown';$Expected='';$Observed='';$Detail='';$CheckedAt=''
 try{
  if($Operation -eq 'FilePush'){
   $Expected='Gönderilen kapsamın dosya içerikleri ve klasörleri kaynakla aynı olmalı.'
   $Evidence=Read-RemoteOpsPushEvidence $Values $ComputerName $PushManifest
   $Code=$Evidence.Status;$Observed=$Evidence.Observed;$Detail=$Evidence.Detail
  }else{
   $Check=[pscustomobject]@{Kind='Service';Path='';Name='';Operator='State';ExpectedType='';Expected=''}
   switch($Operation){
    ServiceControl {$Check.Name=[string]$Values.ServiceName;$Check.Expected=if($Values.Action -eq 'Stop'){'Stopped'}else{'Running'};$Expected=$Check.Name+' · '+$(if($Check.Expected -eq 'Running'){'Çalışıyor'}else{'Durmuş'})}
    ServiceStartup {$Check.Name=[string]$Values.ServiceName;$Check.Operator='Startup';$Check.Expected=[string]$Values.StartupType;$Expected=$Check.Name+' · Başlangıç: '+$Check.Expected}
    RegistryEdit {$Check.Kind='RegistryValue';$Check.Path=[string]$Values.RegistryPath;$Check.Name=[string]$Values.ValueName;$Check.Operator='Equals';$Check.ExpectedType=[string](Get-RemoteOpsPreviewValue $Rows[0] ValueType '');$Check.Expected=[string]$Values.Value;$Expected=$Check.Path+' · '+$Check.Name+' = '+$Check.Expected+' ['+$Check.ExpectedType+']'}
    RegistryDelete {$Check.Kind='RegistryValue';$Check.Path=[string]$Values.RegistryPath;$Check.Name=[string]$Values.ValueName;$Check.Operator='NotExists';$Expected=$Check.Path+' · '+$Check.Name+' bulunmamalı.'}
   }
   $Condition=[pscustomobject]@{Match='All';OnFalse='Stop';Checks=@($Check)}
   $Timer=[Diagnostics.Stopwatch]::StartNew()
   do{
    $Read=Invoke-RemoteOpsConditionChecks $Condition $ComputerName 'PostVerification' $Probe
    $Observed=[string]$Read.Rows[0].Observed
    if($Read.Error){throw [string]$Read.Rows[0].ErrorDetail}
    if($Read.Matched){$Code='Verified';break}
    $Code='Failed'
    if($Operation -ne 'ServiceControl' -or $Timer.Elapsed.TotalSeconds -ge $TimeoutSeconds){break}
    Start-Sleep -Milliseconds 500
   }while($true)
   $Detail=if($Code -eq 'Verified'){'Komuttan sonra hedef tekrar okundu; beklenen sonuç görüldü.'}else{'Komut kabul edildi ancak beklenen sonuç görülmedi. Bu hedefin sonraki adımları çalıştırılmaz.'}
  }
  $CheckedAt=[datetime]::UtcNow.ToString('o')
 }catch{$Code='Unknown';$Detail='Komut kabul edildi; hedefin son durumu doğrulanamadı. '+$_.Exception.Message;$CheckedAt=[datetime]::UtcNow.ToString('o')}
 foreach($Row in $Rows){$Row.VerificationStatus=$Code;$Row.VerificationExpected=$Expected;$Row.VerificationObserved=$Observed;$Row.VerificationDetail=$Detail;$Row.VerifiedAt=$CheckedAt}
}

function Get-RemoteOpsPushManifest {
 param([string]$SourcePath)
 $Roots=if([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($SourcePath)){@(Get-ChildItem -Path $SourcePath -Force -ErrorAction Stop)}else{@(Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop)}
 if(-not $Roots.Count){throw 'Gönderilecek kaynak bulunamadı.'}
 $Items=New-Object Collections.ArrayList;$Stack=New-Object Collections.Stack
 foreach($Root in $Roots){Assert-RemoteOpsVerificationPath $Root.FullName;$Stack.Push([pscustomobject]@{Item=$Root;Relative=$Root.Name})}
 while($Stack.Count){
  $Current=$Stack.Pop();$Item=$Current.Item
  if($Item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Bağlantı/junction içeren kaynak otomatik doğrulanamaz.'}
  $Hash='';$Kind=if($Item.PSIsContainer){'Directory'}else{'File'};$Length=0
  if($Kind -eq 'File'){$Hash=(Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash;$Length=$Item.Length}
  [void]$Items.Add([pscustomobject]@{Relative=$Current.Relative;Kind=$Kind;Length=$Length;Hash=$Hash})
  if($Item.PSIsContainer){foreach($Child in @(Get-ChildItem -LiteralPath $Item.FullName -Force -ErrorAction Stop)){$Stack.Push([pscustomobject]@{Item=$Child;Relative=($Current.Relative+'\'+$Child.Name)})}}
 }
 [pscustomobject]@{SourcePath=$SourcePath;Items=@($Items|Sort-Object Relative);CapturedAt=[datetime]::UtcNow.ToString('o')}
}
function Read-RemoteOpsPushEvidence {
 param($Values,[string]$ComputerName,$Manifest)
 if($null -eq $Manifest -or -not @($Manifest.Items).Count -or $Manifest.SourcePath -cne [string]$Values.LocalPath){throw 'Gönderim öncesi kaynak özeti bulunamadı.'}
 $After=Get-RemoteOpsPushManifest ([string]$Values.LocalPath)
 if((ConvertTo-Json -InputObject @($After.Items) -Depth 5 -Compress) -cne (ConvertTo-Json -InputObject @($Manifest.Items) -Depth 5 -Compress)){throw 'Kaynak gönderim sırasında değişti; içerik doğrulaması kesinleştirilemedi.'}
 $Remote=ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath ([string]$Values.Path)
 Assert-RemoteOpsVerificationPath $Remote
 $Checked=0
 foreach($Expected in $Manifest.Items){
  # Check parents too; never follow a destination junction while hashing.
  $Path=$Remote
  foreach($Part in ([string]$Expected.Relative -split '\\')){
   $Path=Join-Path $Path $Part
   try{$Item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop}catch [System.Management.Automation.ItemNotFoundException]{return [pscustomobject]@{Status='Failed';Observed=('Eksik: '+$Expected.Relative);Detail='Hedefte beklenen dosya veya klasör bulunamadı.'}}
   if($Item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Hedef kapsamda bağlantı/junction bulundu; doğrulanamadı.'}
  }
  if(($Expected.Kind -eq 'Directory') -ne [bool]$Item.PSIsContainer){return [pscustomobject]@{Status='Failed';Observed=$Expected.Relative;Detail='Hedefte dosya/klasör türü farklı.'}}
  if($Expected.Kind -eq 'File'){
   $ActualHash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
   if($ActualHash -ine $Expected.Hash -or $Item.Length -ne $Expected.Length){return [pscustomobject]@{Status='Failed';Observed=($Expected.Relative+' SHA256='+$ActualHash);Detail=('İçerik farklı. Beklenen SHA256='+$Expected.Hash)}}
  }
  $Checked++
 }
 [pscustomobject]@{Status='Verified';Observed=('{0} dosya/klasör kontrol edildi; içerikler aynı.' -f $Checked);Detail='Kaynak değişmedi; gönderilen dosyalar SHA256 ile ve klasörler varlık/tür ile doğrulandı. Hedefteki kapsam dışı dosyalar karşılaştırılmaz.'}
}

function Read-RemoteOpsVerificationProbe {
 param($Check,[string]$ComputerName)
 Read-RemoteOpsConditionProbe $Check $ComputerName
}

function Assert-RemoteOpsVerificationPath {
 param([string]$Path)
 $Current=[IO.Path]::GetFullPath($Path).TrimEnd('\');$Root=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)).TrimEnd('\')
 while($Current.Length -ge $Root.Length -and $Current){
  $Item=Get-Item -LiteralPath ($Current+$(if($Current -match '^[A-Za-z]:$'){'\'}else{''})) -Force -ErrorAction Stop
  if($Item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Doğrulama yolu bağlantı/junction içeriyor: '+$Current)}
  if($Current -ieq $Root){break}
  $Parent=Split-Path $Current -Parent;if(-not $Parent -or $Parent -eq $Current){break};$Current=$Parent.TrimEnd('\')
 }
}
