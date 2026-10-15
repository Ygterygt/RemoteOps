function Get-RemoteOpsPreviewValue {
    param($Object,[string]$Name,$Default='')
    if($null -eq $Object){return $Default}
    if($Object -is [Collections.IDictionary]){if($Object.Contains($Name)){return $Object[$Name]};return $Default}
    $Property=$Object.PSObject.Properties[$Name];if($null -ne $Property){return $Property.Value};return $Default
}
function ConvertTo-RemoteOpsPreviewCanonical {
    param($Value)
    if($null -eq $Value){return $null}
    if($Value -is [Collections.IDictionary]){
        $Result=[ordered]@{};foreach($Key in @($Value.Keys|Sort-Object)){$Result[[string]$Key]=ConvertTo-RemoteOpsPreviewCanonical $Value[$Key]};return $Result
    }
    if($Value -is [System.Management.Automation.PSCustomObject]){
        $Result=[ordered]@{};foreach($Key in @($Value.PSObject.Properties.Name|Sort-Object)){$Result[$Key]=ConvertTo-RemoteOpsPreviewCanonical $Value.$Key};return $Result
    }
    if($Value -is [array]){$Items=@(foreach($Item in $Value){ConvertTo-RemoteOpsPreviewCanonical $Item});return ,$Items}
    return $Value
}
function Get-RemoteOpsPreviewHash {
    param($Value)
    $Json=ConvertTo-Json -InputObject (ConvertTo-RemoteOpsPreviewCanonical $Value) -Depth 30 -Compress
    $Hash=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($Hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Json)))).Replace('-','')}finally{$Hash.Dispose()}
}
function New-RemoteOpsOperationPreview {
    param($Operation,[hashtable]$Values,$Profile,[int]$Parallelism=1,[bool]$CleanupLogs=$false)
    $Targets=@(ConvertTo-RemoteOpsTargets ([string](Get-RemoteOpsPreviewValue $Values Targets)))
    if(-not $Targets.Count){throw 'En az bir hedef bilgisayar girin.'}
    if($null -eq $Profile){throw 'Bir çalıştırma hesabı seçin.'}
    $Name=[string](Get-RemoteOpsPreviewValue $Operation Name)
    if(-not $Name){throw 'Operasyon seçilmedi.'}
    $SafeValues=[ordered]@{};$PrivateHashes=[ordered]@{}
    foreach($Key in @($Values.Keys|Sort-Object)){
        if($Key -in @('Targets','Confirm')){continue}
        if($Key -match '(?i)password|credential|secret|token'){$PrivateHashes[$Key]=Get-RemoteOpsPreviewHash $Values[$Key];continue}
        # Only known form fields and the validated saved-package definition are public.
        $Allowed=@(Get-RemoteOpsPreviewValue $Operation Fields @()|ForEach-Object{Get-RemoteOpsPreviewValue $_ Key})
        if($Key -eq 'PackageDefinition'){$SafeValues[$Key]=Copy-RemoteOpsPackageDefinition $Values[$Key]}
        elseif($Key -in $Allowed){$SafeValues[$Key]=$Values[$Key]}
        else{$PrivateHashes[$Key]=Get-RemoteOpsPreviewHash $Values[$Key]}
    }
    $SafeIdentity=[ordered]@{Id=[string](Get-RemoteOpsPreviewValue $Profile Id);Display=[string](Get-RemoteOpsPreviewValue $Profile Display);Domain=[string](Get-RemoteOpsPreviewValue $Profile Domain);UserName=[string](Get-RemoteOpsPreviewValue $Profile UserName);IsMain=[bool](Get-RemoteOpsPreviewValue $Profile IsMain $false)}
    $OpIdentity=[ordered]@{};foreach($Key in @('Name','Category','Title','ParallelSafe','PluginName','PluginScript','PluginRoot','PluginParallelSafe')){$OpIdentity[$Key]=Get-RemoteOpsPreviewValue $Operation $Key}
    $Snapshot=[ordered]@{Operation=$OpIdentity;Values=$SafeValues;Identity=$SafeIdentity;Targets=$Targets;Parallelism=$Parallelism;CleanupLogs=$CleanupLogs}
    $Fingerprint=Get-RemoteOpsPreviewHash @{Snapshot=$Snapshot;PrivateHashes=$PrivateHashes}
    # Detach all nested data, including the saved package, from mutable form objects.
    $Copy=ConvertFrom-Json (ConvertTo-Json -InputObject $Snapshot -Depth 30)
    $Effects='Bu operasyonun hedefteki etkisi bilinmiyor.';$Rollback='Geri alma desteği bilinmiyor; operasyon sorumlusuyla doğrulayın.'
    $Warnings=@('Yerel önizlemedir. Hedef erişimi, mevcut uygulama/sürüm ve atlama kararı çalıştırmada kontrol edilecek.')
    $ReadOnly=@('ApplicationCheck','ApplicationInventory','FilePull','FileCompare','EndpointInventory','HealthCheck','RegistryRead','ServiceList','ScheduledTaskList','ProcessQuery')
    if($Name -in $ReadOnly){$Effects='Hedeften bilgi/dosya okunur; sonuçlar yerelde oluşturulur.';$Rollback='Hedefte değişiklik beklenmez; geri alma gerekmez.'}
    else{
        switch($Name){
            'PackageTrigger' {$Effects='Seçilen kurulum/kaldırma scripti hedef SYSTEM hesabıyla çalıştırılır.';$Rollback='Paket işlemi genel geri alınabilir transaction değildir; kurtarma paketi ayrıca gerekir.'}
            'PackageDeployment' {$Effects='Kaydedilmiş paket, eylemine göre hedef SYSTEM hesabıyla çalıştırılır.';$Rollback='Paketin eski sürümünü tekrar kurmak ayrı operasyondur; otomatik geri kurulum yoktur.'}
            'FileDelete' {$Effects='Seçili dosyalar zorunlu yedek alındıktan sonra silinir.';$Rollback='Yedek ve manifest mevcutken geri yükleme yapılabilir; saklama süresini kontrol edin.'}
            'FilePush' {$Effects='Kaynak dosya/klasör hedefe gönderilir. Üzerine yazma: '+[string](Get-RemoteOpsPreviewValue $Values Overwrite $false);$Rollback='Üzerine yazılan dosya için otomatik yedek garantisi yoktur.'}
            'FileBrowser' {$Action=[string](Get-RemoteOpsPreviewValue $Values Action);$Effects='Dosya eylemi: '+$Action;$Rollback=if($Action -eq 'Pull'){'Hedefte değişiklik beklenmez.'}else{'Taşıma/değiştirme manifesti ve yedeği mevcutsa ayrı geri alma işlemi kullanılabilir.'}}
            'FileRestore' {$Effects='Seçilen yedek hedefe geri yüklenir; mevcut dosyaların üzerine yazılabilir.';$Rollback='Geri yükleme öncesindeki hedef durumuna otomatik dönüş garantisi yoktur.'}
            'FileRollback' {$Effects='Seçilen dosya işlem manifestinin önceki durumu geri yüklenir.';$Rollback='Yedek/manifest kapsamı ve hedefler çalıştırmada yeniden doğrulanır.'}
            'RegistryEdit' {$Effects='Registry değeri değiştirilir/oluşturulur; Auto mevcut türü korur, açık tür seçimi uyuşmalıdır.';$Rollback='Eski tür/veri değişiklik öncesi kalıcı manifestte saklanır; ayrı geri alma gerekir.'}
            'RegistryDelete' {$Effects='Seçili registry değeri silinir.';$Rollback='Eski tür/veri manifestiyle ayrı geri alma yapılabilir.'}
            'RegistryRollback' {$Effects='Seçilen manifestin registry türü ve eski değeri geri yüklenir.';$Rollback='Canlı hedef ile yedek kapsamı çalıştırmada doğrulanır.'}
            'ServiceControl' {$Effects='Servis eylemi uygulanır: '+[string](Get-RemoteOpsPreviewValue $Values Action);$Rollback='Kaydedilen eski durum manifestiyle ayrı servis geri alma yapılabilir.'}
            'ServiceStartup' {$Effects='Servis başlangıç türü değiştirilir.';$Rollback='Eski başlangıç türü manifestiyle ayrı geri alma yapılabilir.'}
            'ServiceTaskRollback' {$Effects='Seçilen servis/görev manifesti geri yüklenir.';$Rollback='Mevcut manifest ve hedef kapsamı yeniden doğrulanır.'}
            'ScheduledTaskDelete' {$Effects='Zamanlanmış görev XML yedeği alındıktan sonra silinir.';$Rollback='XML yedeği ve manifest mevcutken ayrı geri alma yapılabilir.'}
            'ScheduledTaskAction' {$Action=[string](Get-RemoteOpsPreviewValue $Values Action);$Effects='Zamanlanmış görev eylemi: '+$Action;$Rollback=if($Action -eq 'Run'){'Görevin çalıştırılmasının yan etkileri geri alınamaz olabilir.'}else{'Etkinlik durumu kaydedilen manifestle geri alınabilir.'}}
            'ProcessKill' {$Effects='Seçilen süreç sonlandırılır.';$Rollback='Süreç sonlandırma geri alınamaz; uygulamayı yeniden başlatma ayrı iştir.'}
            default {$Warnings+=@('Eklenti/özel operasyon etkisi bilinmiyor; açıklamayı ve sorumlusunu kontrol edin.')}
        }
    }
    if($Name -in @('PackageDeployment','PackageTrigger')){
        $Action=[string](Get-RemoteOpsPreviewValue $Values Action)
        if($Name -eq 'PackageDeployment'){
            $P=Get-RemoteOpsPreviewValue $Values PackageDefinition;$Part=Get-RemoteOpsPreviewValue $P $Action
            $Mode=[string](Get-RemoteOpsPreviewValue $Part CheckMode)
            if($Action -eq 'Downgrade'){$Effects+=' Kaldırma → yokluk doğrulama → ayrı eski sürüm kurulumu → tam sürüm doğrulama.';$Warnings+=@('Yeniden başlatma gereksiniminde zincir durur. Kaldırma sonrası kurulum başarısız olabilir; kurtarma sorumlusu belirlenmelidir.')}
        }else{$Mode=[string](Get-RemoteOpsPreviewValue $Values CheckMode);if(-not [string](Get-RemoteOpsPreviewValue $Values Application)){$Mode='Trigger without checks'}}
        if($Mode -eq 'Trigger without checks'){$Warnings+=@('Kontrolsüz tetikleme: uygulama varlığı/sürümü doğrulanmayacak.')}
    }
    if($CleanupLogs){$Warnings+=@('Log temizleme ayarı açık. Paket/log toplama koşulları sağlanırsa hedefte toplanan uygun loglar silinebilir.')}
    if($PrivateHashes.Count){$Warnings+=@('Özel/gizli alanların değerleri bu özette gösterilmedi.')}
    return [pscustomobject]@{Operation=$Copy.Operation;Targets=@($Copy.Targets);Identity=$Copy.Identity;Parameters=$Copy.Values;Effects=$Effects;Rollback=$Rollback;Warnings=$Warnings;Snapshot=$Copy;Fingerprint=$Fingerprint}
}
function Test-RemoteOpsOperationPreviewCurrent {
    param($Preview,$Operation,[hashtable]$Values,$Profile,[int]$Parallelism=1,[bool]$CleanupLogs=$false)
    try{return $Preview.Fingerprint -ceq (New-RemoteOpsOperationPreview $Operation $Values $Profile $Parallelism $CleanupLogs).Fingerprint}catch{return $false}
}
function Format-RemoteOpsOperationPreview {
    param($Preview)
    $ParameterText=@(foreach($Property in $Preview.Parameters.PSObject.Properties){
        $Value=$Property.Value
        if($Property.Name -eq 'PackageDefinition'){
            $Action=[string](Get-RemoteOpsPreviewValue $Preview.Parameters Action)
            $Parts=if($Action -eq 'Downgrade'){@('Uninstall','Downgrade')}else{@($Action)}
            'Paket: '+$Value.Name+' | Kimlik: '+$Value.Id+' | Revizyon: '+$Value.Revision
            'Hedef sürüm: '+$(if($Action -eq 'Downgrade'){$Value.DowngradeVersion}else{$Value.TargetVersion})
            foreach($PartName in $Parts){
                $Part=Get-RemoteOpsPreviewValue $Value $PartName
                $Label=switch($PartName){Install{'Kurulum'} Uninstall{'Kaldırma'} Downgrade{'Eski sürüm kurulumu'} default{$PartName}}
                $Label+': '+[string](Get-RemoteOpsPreviewValue $Part PackagePath)+'\'+[string](Get-RemoteOpsPreviewValue $Part PackageFile)
                '  Kimlik: '+[string](Get-RemoteOpsPreviewValue $Part SearchType)+' / '+[string](Get-RemoteOpsPreviewValue $Part Application)
                '  Registry anahtarı: '+[string](Get-RemoteOpsPreviewValue $Part RegistryKey)+' | Kontrol: '+[string](Get-RemoteOpsPreviewValue $Part CheckMode)
            }
            continue
        }
        $Text=if($Value -is [string]){if($Value.Length){$Value}else{'[boş metin]'}}else{ConvertTo-Json -InputObject $Value -Depth 15}
        $Property.Name+': '+$Text
    }) -join "`r`n"
    return @(
        ('Operasyon: '+$Preview.Operation.Title+' ('+$Preview.Operation.Name+')'),
        ('Hesap: '+$Preview.Identity.Display+' | Mevcut Windows oturumu: '+$Preview.Identity.IsMain),
        ('Eşzamanlı hedef: '+$Preview.Snapshot.Parallelism),('Bilgisayar sayısı: '+$Preview.Targets.Count),
        ($Preview.Targets -join ', '),'','İŞLEM ETKİSİ',$Preview.Effects,'','GERİ ALMA',$Preview.Rollback,
        '','PARAMETRELER',$ParameterText,'','KONTROL NOTLARI',($Preview.Warnings -join "`r`n")
    ) -join "`r`n"
}
