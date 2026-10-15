. (Join-Path $PSScriptRoot 'RemoteOps.Verification.ps1')
function ConvertTo-RemoteOpsStepViews {
 param([object[]]$Rows)
 $Groups=[ordered]@{};$Index=0
 foreach($Row in $Rows){$Index++;$Number=Get-RemoteOpsPreviewValue $Row StepIndex ''; $Key=if($Number){[string]$Number}else{'row'+$Index};if(-not $Groups.Contains($Key)){$Groups[$Key]=@()};$Groups[$Key]+=,$Row}
 foreach($Group in $Groups.Values){
  $Row=$Group[0];$Op=[string](Get-RemoteOpsPreviewValue $Row Operation '');$Status=[string](Get-RemoteOpsPreviewValue $Row Status (Get-RemoteOpsPreviewValue $Row Durum ''))
  $Code=[string](Get-RemoteOpsPreviewValue $Row VerificationStatus '')
  $Reason=[string](Get-RemoteOpsPreviewValue $Row StepResultReason (Get-RemoteOpsPreviewValue $Row VerificationDetail (Get-RemoteOpsPreviewValue $Row ErrorDetail (Get-RemoteOpsPreviewValue $Row HataDetayi ''))))
  $VerificationDetail=[string](Get-RemoteOpsPreviewValue $Row VerificationDetail '');if($VerificationDetail -and $Reason -cne $VerificationDetail){$Reason+=' '+$VerificationDetail}
  foreach($R in $Group){foreach($Field in @('ErrorDetail','HataDetayi')){$ErrorText=[string](Get-RemoteOpsPreviewValue $R $Field '');if($ErrorText -and -not $Reason.Contains($ErrorText)){$Reason+=' '+$ErrorText}}}
  $Name=[string](Get-RemoteOpsPreviewValue $Row StepName '');if(-not $Name){$Name=$Op}
  $Command=switch($Status){Success{'Kabul edildi'}NotRun{'Çalıştırılmadı'}Skipped{'Çalıştırılmadı'}default{$Status}}
  $Result=if($Status -eq 'NotRun'){'Çalıştırılmadı'}elseif($Status -eq 'Skipped'){'Atlandı'}elseif($Code -eq 'Verified'){'Tamamlandı'}elseif($Code -eq 'Failed'){'Beklenen sonuç oluşmadı'}elseif($Code -eq 'Unknown'){'Sonuç belirsiz'}elseif($Op -eq 'RecipeCondition'){'Koşul kontrolü'}else{$Status}
  $Observed=[string](Get-RemoteOpsPreviewValue $Row VerificationObserved '');$Expected=[string](Get-RemoteOpsPreviewValue $Row VerificationExpected '')
  if($Op -eq 'RecipeCondition'){$Observed=@($Group|ForEach-Object{Get-RemoteOpsPreviewValue $_ Observed ''}) -join '; ';$Expected=@($Group|ForEach-Object{Get-RemoteOpsPreviewValue $_ Expected ''}) -join '; '}
  if($Op -in @('ServiceList','RegistryRead','FileCompare','RecipeCondition') -and $Status -in @('Success','NotFound','Esit','Farkli')){$Code='NotRequired';$Command='Kontrol edildi'}
  if($Status -in @('NotRun','Skipped')){$Code='NotPerformed'}
  [pscustomobject]@{Number=(Get-RemoteOpsPreviewValue $Row StepIndex '');Name=$Name;Result=$Result;Command=$Command;Verification=(Get-RemoteOpsVerificationLabel $Code);Reason=$Reason;Expected=$Expected;Observed=$Observed;CheckedAt=[string](Get-RemoteOpsPreviewValue $Row VerifiedAt '');SourceRows=@($Group)}
 }
}
function Get-RemoteOpsStepViewDetail {
 param($View)
 if($null -eq $View){return 'Bir adım seçin. Beklenen sonuç, gözlenen durum ve açıklama burada görünür.'}
 ('Beklenen: '+$View.Expected+"`r`n"+'Gözlenen: '+$View.Observed+"`r`n"+'Açıklama: '+$View.Reason+"`r`n"+'Kontrol zamanı (UTC): '+$View.CheckedAt)
}
function Set-RemoteOpsStepResultGrid {
 param($Grid,[object[]]$Rows)
 $Friendly=@($Rows|Where-Object{(Get-RemoteOpsPreviewValue $_ StepIndex '') -or (Get-RemoteOpsPreviewValue $_ VerificationStatus '')}).Count -gt 0
 $Grid.ItemsSource=@();$Grid.Columns.Clear();$Grid.AutoGenerateColumns=-not $Friendly
 if($Friendly){
  foreach($Pair in @(@('Number','#','36'),@('Name','Adım','*'),@('Command','Komut','110'),@('Verification','Sonuç doğrulaması','200'))){
   $Column=New-Object Windows.Controls.DataGridTextColumn;$Column.Header=$Pair[1];$Column.Binding=New-Object Windows.Data.Binding $Pair[0];$Column.Width=[Windows.Controls.DataGridLengthConverter]::new().ConvertFromString($Pair[2]);if($Pair[0] -eq 'Name'){$Column.MinWidth=200};[void]$Grid.Columns.Add($Column)
  }
  $Grid.ItemsSource=@(ConvertTo-RemoteOpsStepViews $Rows)
 }else{$Grid.ItemsSource=@($Rows)}
 $Grid.Tag.Visibility=if($Friendly){'Visible'}else{'Collapsed'}
 $Grid.Tag.Text=Get-RemoteOpsStepViewDetail $null
 if($Grid.Items.Count -gt 0){$Grid.SelectedIndex=0}
}
function Get-RemoteOpsStepSummaryHtml {
 param([object[]]$Rows)
 $Parts=New-Object Collections.ArrayList
 foreach($Computer in @($Rows|ForEach-Object{Get-RemoteOpsPreviewValue $_ ComputerName (Get-RemoteOpsPreviewValue $_ IstemciAdi '')}|Select-Object -Unique)){
  $TargetRows=@($Rows|Where-Object{(Get-RemoteOpsPreviewValue $_ ComputerName (Get-RemoteOpsPreviewValue $_ IstemciAdi '')) -ceq $Computer})
  foreach($V in @(ConvertTo-RemoteOpsStepViews $TargetRows)){
   $Class=if($V.Result -in @('Beklenen sonuç oluşmadı','Sonuç belirsiz')){'bad'}else{''}
   $Cells=@($Computer,$V.Number,$V.Name,$V.Command,$V.Verification,$V.Result,$V.Reason,$V.Expected,$V.Observed,$V.CheckedAt)
   [void]$Parts.Add(('<tr class="'+$Class+'">')+(@($Cells|ForEach-Object{'<td>'+[Net.WebUtility]::HtmlEncode([string]$_)+'</td>'}) -join '')+'</tr>')
  }
 }
 '<section class="panel"><h2>Adım sonuçları</h2><p>Komut yanıtı ve son durum kontrolü ayrı gösterilir. Bu sonuç, kontrol anının kaydıdır.</p><div class="table-wrap"><table><thead><tr><th>Bilgisayar</th><th>#</th><th>Adım</th><th>Komut</th><th>Sonuç doğrulaması</th><th>Adım sonucu</th><th>Açıklama</th><th>Beklenen</th><th>Gözlenen</th><th>Kontrol zamanı (UTC)</th></tr></thead><tbody>'+($Parts -join '')+'</tbody></table></div></section>'
}
