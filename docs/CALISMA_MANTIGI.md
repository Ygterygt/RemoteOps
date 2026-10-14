# RemoteOps çalışma mantığı

14 Ekim 2026 · YD_RemoteOps.App_v11 · Mimari akış rehberi

GUI operatörün girdilerini ayrı Runner'a aktarır. Runner hedefe uygun yöntemle gider; sonucu yerel çalışma dosyalarına yazar. GUI bu dosyaları okuyarak ilerleme ve sonuç gösterir. Şirket pilotundan ilk geri bildirim alındı; tam kabul matrisi henüz tamamlanmadı.

## 1. Genel süreç zinciri

```text
YD_RemoteOps.App.bat
 -> RemoteOps.App/RemoteOps.App.bat
 -> RemoteOps.App.ps1 [WPF]
    -> Hesap + eylem + hedefler + doğrulanmış girdiler
    -> UTF-8 JSON / Base64 Request
       -> RemoteOps.Runner.ps1 [ayrı Windows PowerShell]
          -> Sıralı hedef veya paralel tek-hedef worker
          -> WMI/CIM/DCOM | SMB | PsExec SYSTEM
          -> Sonuç + aktivite + checkpoint + ledger
    <- 500 ms stdout/stderr/progress okuma
    <- Results HTML/CSV ve günlük Rapor
```

Main mevcut Windows token'ını kullanır. Alternatif profil Windows credential API'siyle cmd.exe, ardından Runner PowerShell'i başlatır. Parola request veya komut satırında bulunmaz. Hedef paket PsExec -s ile SYSTEM altında çalışır.

## 2. Dosyaların ilişkisi

| Katman | Dosyalar / işlev |
| --- | --- |
| Başlatma | İki BAT; Windows PowerShell 5.1/STA. |
| GUI | App.ps1, PackageUi.ps1; profiller, alanlar, paket ekranları, izleme. |
| Kayıt | Packages.ps1; şema, kişisel katalog, revizyon, snapshot. |
| Motor | Deployment.ps1; Runner'ın Detect/ValidateSource/Execute callback'leri. |
| Dayanıklı durum | RunState.ps1; iptal/checkpoint/kısmi rapor kurtarma. |
| Uzak iş | ApplicationWorkers.ps1 ve diğer beş Modules dosyasının ilgili fonksiyonları. |
| Rapor | Reports.ps1; çalışma CSV/HTML ve günlük ledger. |

ApplicationWorkers içindeki RegistryCheckScript, InstalledApplicationInventoryScript ve PackageScript AST ile çıkarılır. Diğer menü modüllerine Read-Host FIFO cevap kuyruğuyla uyarlama yapılır. Soru/menü sırası değişirse Runner cevapları birlikte güncellenir. Bu dağıtımda eski MD/CLM ve örnek eklenti dosyaları yoktur; GUI bunlara bağlı değildir. Modules klasöründe toplam altı modül vardır.

## 3. Paket kaydından çalıştırmaya

```text
Paket Oluştur -> doğrulama -> kişisel JSON katalog
Paketlerim -> seçim -> hesap/hedefler -> özet/onay
 -> bağımsız snapshot -> Runner
 -> hedef/aile yerel kilidi
 -> tespit/karar -> kaynak erişimi -> paket adımı
 -> son tespit -> terminal hedef sonucu -> rapor/ledger
```

Paket Oluştur MSI/EXE üretmez; hazır .bat/.cmd/.ps1/.vbs dosyasını tarif eder. Katalog %APPDATA%\MDRemoteOps\Packages altındadır. Tanım bağımsız normal kurulum/kaldırma/eski sürüm kimlikleri ve kaynakları içerir; parola/hedef/onay içermez. Kaydetme uzak işlem yapmaz. Runner katalog dosyasını tekrar açmaz; request snapshot'ını kullanır. Snapshot raporda PackageDefinition.json olarak saklanır.

## 4. Hangi yöntemle nereye gider?

| İş | Yöntem / kimlik |
| --- | --- |
| Profil/katalog | Yerel APPDATA; GUI operatörü. |
| Uygulama tespiti | HKLM uninstall/WOW6432Node, StdRegProv; Runner hesabı. |
| Dosya ve log | \\PC\C$ gibi SMB yönetim paylaşımı; Runner hesabı. |
| Envanter/servis/görev/süreç | CIM/DCOM; Runner hesabı. |
| Kaynak probe/paket | PsExec hedef SYSTEM; tam kaynak dosyası probe ve etkileşimsiz wrapper. |
| Rapor/yedek/checkpoint | C:\Temp\YD_RemoteOps.App; ilgili yerel süreç kimliği. |

Standart iş WinRM oturumuna dayanmaz; Win32_Product kullanılmaz. Operatör UNC erişimi ve hedef SYSTEM UNC erişimi ayrı koşullardır. Probe scriptin çağırdığı tüm ek dosyaları doğrulamaz.

## 5. Kur/kaldır/downgrade

Normal Version controlled Kur hedef/üst sürüm varsa atlar ve kurulum sonrası hedef/üst sürümü kabul eder. Presence only varlığı sınar. Trigger without checks uygulama durumunu kanıtlamaz.

```text
Daha yeni sürüm + doğru kaldırma kimliği
 -> İki kaynağı doğrula -- erişim yok -> Error; değişiklik yok
 -> Kaldır -- hata/belirsiz/reboot -> dur
 -> Yokluğu doğrula -- hâlâ var -> Error; kurulum yok
 -> Kur
 -> Yeni kimlik + tam hedef sürüm -> terminal sonuç
```

Downgrade eşit/eski/yok uygulamayı atlar. Kimlik/sürüm belirsizse mutasyon yapılmaz. Kaldırma 3010/1641 ise RebootRequired ile durur. Otomatik reboot/retry/geri kurulum yoktur. Kaldırma başarılı, kurulum başarısızsa bu durum adım kayıtlarında korunur.

## 6. Paralellik ve kesinti

İzin verilen operasyonlar 1–10 tek-hedef worker ile yürüyebilir; mutasyonların kalan kısmı sıralıdır. Hedef/aile kilidi aynı veri kökünde çakışmayı engeller; farklı operatör bilgisayarlarını koordine etmez.

Kaydedilmiş dağıtımda Durdur iptal marker'ı yazar; yeni hedef/adım başlamaz, aktif adım beklenir. Zorla durdur yerel süreç ağacını kapatır; uzaktaki paket devam edebilir. Checkpoint varsa terminal sonuç korunur. Başlamayan iptal hedef Cancelled, doğrulanmamış mutasyon Indeterminate olur. Tam GUI çökmesinden sonra otomatik resume yoktur. Diğer operasyonların Durdur davranışı yerel süreç sonlandırmadır.

## 7. Çıktı ve sayım

Results çalışma sonuçları, Activity aktivite, RemoteOps.log teknik tanı, PackageDefinition.json kullanılan tanımdır. Workers paralel çıktı, Detail modül ara raporlarıdır. Ledger hedef başına terminal sonucu günlük Rapor'a taşır; downgrade iki hedef gibi sayılmaz.

Success, Skipped, Error, Unreachable, Cancelled, Indeterminate, RebootRequired farklı durumlardır. İlerleme çubuğunun bitmesi bütün hedeflerin başarılı olduğunu göstermez. Belirsiz uzak sonuç hedefte doğrulanmadan tekrar dağıtım yapılmaz.

Operatör adımları [kılavuzda](KULLANIM_KILAVUZU.md), gerçek test kaydı [pilot tablosunda](PAKET_YONETIMI_PILOT_KONTROLU.md), bütün dosya/operasyon haritası ve bakım sözleşmesi [teknik el kitabındadır](TEKNIK_EL_KITABI.md).


## 8. Eski sürüm paketi ayrıdır

Kur eylemi Install/TargetVersion kullanır. Kaldır eylemi yalnızca Uninstall tanımını kullanır; tek başına önceki sürümü geri getirmez. Eski sürüme dön, Uninstall -> yokluk doğrulaması -> Downgrade/Exact -> DowngradeVersion tam doğrulaması zinciridir. Normal Install paketi bu zincirde seçilmez. Yeni kayıt/aktarımı /2 sürümlüdür; /1 tanımlar okuma sırasında önceki downgrade anlamı korunarak dönüştürülür.


## 9. v11 hedef erişim akışı

İstek ve onay doğrulaması > operasyon/eklenti doğrulaması > hedefe uygun salt okunur SMB veya yönetim erişimi > erişim başarılıysa mevcut işlem akışı > tek hedef sonucu > ortak rapor.

Erişilemeyen hedefte işlem başlatılmaz; Unreachable teknik sonucu sarı Atlandı - Erişilemedi olarak sunulur. Yetki reddi ve gerçek işlem hataları kırmızıdır. Kayıtlı kontrolsüz script sürüm/uygulama sorgusu yapmaz, SMB üzerinden mevcut paket mekanizmasıyla çalışır. İşlem öncesi kontrol her hedef için, o hedefin sırası geldiğinde yapılır; paralel worker'lar aynı kapıyı kullanır.
