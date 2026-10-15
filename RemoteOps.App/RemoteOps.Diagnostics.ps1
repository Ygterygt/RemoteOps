function Get-RemoteOpsDiagnosis {
    param($Run,[string]$ComputerName,$Details)
    $Rows=@($Details.Rows|Where-Object{(Get-RemoteOpsHistoryRowComputer $_) -eq $ComputerName})
    $Target=@($Details.Targets|Where-Object ComputerName -eq $ComputerName|Select-Object -First 1)
    $Outcome=if($Target.Count){[string]$Target[0].Outcome}else{'Unknown'}
    $Evidence=New-Object System.Collections.ArrayList
    foreach($Row in $Rows){
        $Step=Get-RemoteOpsRowValue $Row @('StepName','Step','Action')
        $Status=Get-RemoteOpsRowValue $Row @('Status','ExecutionStatus','Durum')
        $Code=Get-RemoteOpsRowValue $Row @('ExitCode','ReturnValue')
        $Message=Get-RemoteOpsRowValue $Row @('VerificationDetail','ErrorDetail','HataDetayi','PostCheckErrorDetail','Detail')
        [void]$Evidence.Add(('{0} | {1} | Code: {2} | {3}' -f $Step,$Status,$Code,$Message))
    }
    if($Target.Count -and $Target[0].Detail){[void]$Evidence.Add([string]$Target[0].Detail)}
    $Reboot=@($Rows|Where-Object{(Get-RemoteOpsRowValue $_ @('ExitCode')) -in @('3010','1641') -or (Get-RemoteOpsRowValue $_ @('RebootRequired')) -eq 'True'}).Count -gt 0 -or $Outcome -eq 'RebootRequired'
    $Text=$Evidence -join "`r`n"
    $Category='Unknown';$Checks=@('Özgün sonuç ve teknik logları inceleyin; mevcut kanıt kesin neden belirlemek için yeterli olmayabilir.')
    if($Outcome -eq 'Indeterminate'){$Category='Indeterminate';$Checks=@('Uzak işlem hâlâ çalışıyor olabilir. Yeniden tetiklemeden önce çalışan yükleyiciyi ve uygulamanın mevcut sürümünü kontrol edin.')}
    elseif($Outcome -eq 'Unreachable'){$Category='Unreachable';$Checks=@('Hedef adı ve ağ erişimini, operasyonun gerektirdiği SMB ve WMI/DCOM bağlantılarını kontrol edin.')}
    elseif($Outcome -eq 'RebootRequired'){$Category='RebootRequired';$Checks=@('Planlı yeniden başlatma durumunu kontrol edin; sonrasında uygulama varlığını ve sürümünü yeniden doğrulayın.')}
    elseif($Outcome -in @('Success','Skipped','Cancelled')){$Category=$Outcome;$Checks=@('Özgün hedef sonucu ve adım kayıtları aşağıdadır. Yeni işlem başlatılmaz.')}
    elseif($Text -match '(?i)access denied|accessdenied|yetki|erişim redd|0x80070005' -or @($Rows|Where-Object{(Get-RemoteOpsRowValue $_ @('ExitCode')) -eq '5'}).Count){$Category='AccessDenied';$Checks=@('Seçilen hesabın hedef yetkilerini kontrol edin. Operatör hesabı ile hedef SYSTEM kaynak erişiminin ayrı koşullar olduğunu dikkate alın.')}
    elseif($Text -match '(?i)ValidateSource|SourceProbe|source inaccessible|kaynak.*eriş|kaynak.*bulun'){$Category='Source';$Checks=@('Paket kaynağını ve bağımlı dosyaları hem seçilen hesap hem hedef SYSTEM erişimiyle kontrol edin.')}
    elseif($Text -match '(?i)VerifyInstall|VerifyUninstall|VerifyVersion|verification failed|son.*doğrula'){$Category='Verification';$Checks=@('İşlem sonrası gerçek uygulama kimliğini ve sürümünü kontrol edin; paket çıkış kodunu tek başına başarı kanıtı saymayın.')}
    elseif($Rows.Count){$Category='Execution';$Checks=@('Paketin veya operasyonun özgün çıkış kodunu ve ilgili loglarını inceleyin. Bilinmeyen kodlara otomatik kök neden atanmaz.')}
    if($Reboot -and $Outcome -ne 'RebootRequired'){$Checks+=@('Çıkış kaydı yeniden başlatma gereksinimi/başlatıldığını bildiriyor (3010/1641). Başarı durumu değiştirilmedi.')}
    $Reasons=@{
      Success='İşlem kayıtlarda başarılı olarak tamamlandı.'
      Skipped='İşlem atlandı. Kayıt, atlama nedenini kesinleştirmek için incelenmelidir.'
      Cancelled='İşlem iptal edildi; bazı adımlar önceden tamamlanmış olabilir.'
      Indeterminate='İşlemin tamamlandığı doğrulanamadı; hedefte hâlâ çalışıyor olabilir.'
      Unreachable='İşlem sırasında hedef bilgisayara erişilemedi.'
      RebootRequired='Sonuç kaydı yeniden başlatma gerektiğini bildiriyor.'
      AccessDenied='Kayıtlarda yetki veya erişim reddi işareti var; kesin neden ayrıca doğrulanmalıdır.'
      Source='Kayıtlarda kaynak dosyaya erişim sorunu işareti var.'
      Verification='İşlem sonrası beklenen durum doğrulanamadı.'
      Execution='Operasyon hata bildirdi; mevcut kayıt tek başına kesin nedeni açıklamıyor.'
      Unknown='Nedeni belirlemek için yeterli sonuç kaydı yok.'
    }
    $Reason=$Reasons[$Category];$NextAction=$Checks -join ' '
    if($Category -eq 'Skipped' -and $Text -match '(?i)Target or newer version already installed'){
      $Reason='Hedefte aynı veya daha yeni sürüm bulunduğu için kurulum atlandı.'
      $NextAction='İstenen sürüm ile hedefte kayıtlı sürümü kontrol edin. Bu sonuç tek başına hata değildir.'
    }elseif($Category -eq 'Success'){$NextAction='Sonuçları inceleyin; bu kayıt tek başına yeni işlem gerektirmiyor.'}
    elseif($Category -eq 'Cancelled'){$NextAction='Tamamlanan adımları ve hedefin mevcut durumunu kontrol ederek yeniden çalıştırmaya karar verin.'}
    if($Reboot -and $Category -eq 'Success'){$NextAction='Sonuç başarılı bildirildi; yeniden başlatma gereksinimi veya başlatılmış olması işaretini kontrol edin. Planlı yeniden başlatma sonrasında durumu doğrulayın.'}
    $VerificationRows=@($Rows|Where-Object{(Get-RemoteOpsRowValue $_ @('VerificationStatus')) -in @('Failed','Unknown')})
    if($VerificationRows.Count){
      $Category='Verification';$Reason=if(@($VerificationRows|Where-Object{(Get-RemoteOpsRowValue $_ @('VerificationStatus')) -eq 'Unknown'}).Count){'Komut kabul edildi; hedefin son durumu okunamadı veya doğrulama kesinleştirilemedi.'}else{'Komut kabul edildi ancak hedefte beklenen sonuç oluşmadı.'}
      $NextAction='Adım ayrıntısındaki beklenen ve gözlenen durumu karşılaştırın. Önceden tamamlanan adımlar geri alınmadı; hedefin mevcut durumunu kontrol ederek yeniden çalıştırmaya karar verin.'
      $Checks=@($NextAction)
    }
    $Fields=@{}
    foreach($Name in @('PackageId','PackageRevision','PreviousVersion','TargetVersion','FinalVersion')){
        $Fields[$Name]=''
        foreach($Row in $Rows){$Value=Get-RemoteOpsRowValue $Row @($Name);if($Value){$Fields[$Name]=$Value}}
    }
    return [pscustomobject]@{OperationID=$Run.OperationID;ComputerName=$ComputerName;Outcome=$Outcome;Category=$Category;Reason=$Reason;NextAction=$NextAction;Evidence=@($Evidence);Checks=$Checks;Rows=$Rows;RebootRequired=$Reboot;PackageId=$Fields.PackageId;PackageRevision=$Fields.PackageRevision;PreviousVersion=$Fields.PreviousVersion;TargetVersion=$Fields.TargetVersion;FinalVersion=$Fields.FinalVersion}
}
function Get-RemoteOpsDiagnosticFiles {
    param([string]$BasePath,$Run)
    $Files=New-Object System.Collections.ArrayList;$Issues=New-Object System.Collections.ArrayList
    $Details=Get-RemoteOpsHistoryDetails $BasePath $Run
    # Validate exact operation/run folder, not merely a common prefix.
    $Folder=@($Details.Artifacts|Where-Object{ $_.Kind -eq 'Folder' -and $_.Exists})
    if($Folder.Count -ne 1){throw 'Verified report folder is not available.'}
    $ReportRoot=$Folder[0].Path
    $Candidates=@($Details.Artifacts|Where-Object{$_.Kind -ne 'Folder' -and $_.Exists}|ForEach-Object{$_.Path})
    $Workers=Resolve-RemoteOpsHistoryPath $BasePath (Join-Path $ReportRoot 'Workers')
    if(Test-Path -LiteralPath $Workers -PathType Container){
        $Candidates+=@(Get-ChildItem -LiteralPath $Workers -File|Where-Object{$_.Name -cmatch '^\d+\.(out|err)\.log$'}|ForEach-Object{$_.FullName})
    }
    foreach($Path in @($Candidates|Select-Object -Unique)){
        try{
            $Full=Resolve-RemoteOpsHistoryPath $BasePath $Path
            if(-not $Full.StartsWith($ReportRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'File outside selected report.'}
            $Item=Get-Item -LiteralPath $Full -ErrorAction Stop
            [void]$Files.Add([pscustomobject]@{Path=$Full;RelativePath=$Full.Substring($ReportRoot.Length+1).Replace('\','/');Length=$Item.Length;Hash=(Get-FileHash -LiteralPath $Full -Algorithm SHA256).Hash})
        }catch{[void]$Issues.Add([pscustomobject]@{Path=$Path;Message=$_.Exception.Message})}
    }
    return [pscustomobject]@{Files=@($Files);Issues=@($Issues)}
}
function Export-RemoteOpsDiagnosticBundle {
    param([string]$BasePath,$Run,[object[]]$ApprovedFiles,[string]$Destination)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if(@($ApprovedFiles).Count -eq 0){throw 'No diagnostic files selected.'}
    $Current=Get-RemoteOpsDiagnosticFiles $BasePath $Run
    if($Current.Issues.Count){throw 'Diagnostic sources could not all be validated.'}
    $Map=@{};foreach($File in $Current.Files){$Map[$File.Path]=$File}
    $Seen=@{};$Selected=@(foreach($Approved in $ApprovedFiles){
        if(-not $Map.ContainsKey([string]$Approved.Path)){throw 'File is not in the report allowlist.'}
        $File=$Map[[string]$Approved.Path]
        if($Seen.ContainsKey($File.Path)){throw 'Duplicate archive file.'};$Seen[$File.Path]=$true
        if($File.Hash -ne $Approved.Hash -or $File.Length -ne $Approved.Length -or $File.RelativePath -cne $Approved.RelativePath){throw 'Source changed since preview; refresh the file list.'}
        $File
    })
    $FullDestination=[IO.Path]::GetFullPath($Destination)
    if([IO.Path]::GetExtension($FullDestination) -ine '.zip'){throw 'Destination must have a .zip extension.'}
    $Output=$null;$Archive=$null;$Created=$false
    try{
        $Output=[IO.File]::Open($FullDestination,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$Created=$true
        $Archive=New-Object IO.Compression.ZipArchive -ArgumentList $Output,([IO.Compression.ZipArchiveMode]::Create),$true
        foreach($File in $Selected){
            [void](Resolve-RemoteOpsHistoryPath $BasePath $File.Path)
            $InputStream=[IO.File]::Open($File.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try{
                $Hasher=[Security.Cryptography.SHA256]::Create()
                try{$Hash=([BitConverter]::ToString($Hasher.ComputeHash($InputStream))).Replace('-','')}finally{$Hasher.Dispose()}
                if($Hash -ne $File.Hash){throw 'Source changed during export.'}
                $InputStream.Position=0
                $Entry=$Archive.CreateEntry($File.RelativePath)
                $Target=$Entry.Open();try{$InputStream.CopyTo($Target)}finally{$Target.Dispose()}
            }finally{$InputStream.Dispose()}
        }
        $Archive.Dispose();$Archive=$null;$Output.Dispose();$Output=$null
        $Verify=[IO.Compression.ZipFile]::OpenRead($FullDestination)
        try{
            if($Verify.Entries.Count -ne $Selected.Count){throw 'ZIP entry count mismatch.'}
            foreach($File in $Selected){
                $Entry=$Verify.GetEntry($File.RelativePath);if($null -eq $Entry){throw 'ZIP entry is missing.'}
                $Stream=$Entry.Open();$Hasher=[Security.Cryptography.SHA256]::Create()
                try{$Hash=([BitConverter]::ToString($Hasher.ComputeHash($Stream))).Replace('-','')}finally{$Hasher.Dispose();$Stream.Dispose()}
                if($Hash -ne $File.Hash){throw 'ZIP content verification failed.'}
            }
        }finally{$Verify.Dispose()}
        return [pscustomobject]@{Path=$FullDestination;Bytes=(Get-Item -LiteralPath $FullDestination).Length;EntryCount=$Selected.Count}
    }catch{
        if($null -ne $Archive){$Archive.Dispose();$Archive=$null};if($null -ne $Output){$Output.Dispose();$Output=$null}
        if($Created -and [IO.File]::Exists($FullDestination)){[IO.File]::Delete($FullDestination)}
        throw
    }finally{if($null -ne $Archive){$Archive.Dispose()};if($null -ne $Output){$Output.Dispose()}}
}
