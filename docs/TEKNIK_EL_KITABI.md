# RemoteOps teknik el kitabı

14 Ekim 2026 · YD_RemoteOps.App_v11 · Mevcut kaynak kodun çalışma sözleşmesi

Bu el kitabı şirket bilgisayarına taşınacak paketin yapısını, hesap sınırlarını, uzak erişim yöntemlerini ve sonuçların nerede tutulduğunu açıklar. Yerel doğrulamalar şirket ağında yapılmış bir dağıtım testi yerine geçmez. İlk pilot geri bildirimi işlendi; tam kabul matrisi operatör tarafından tamamlanacaktır. Sürüm adı klasörün dağıtım adıdır; otomatik güncelleme veya imzalı sürüm yönetimi uygulanmaz.

## 1. Amaç ve kapsam

RemoteOps, Windows uç noktalarda yazılım dağıtımı ve bakım işlemleri için Windows PowerShell 5.1 üzerinde çalışan bir WPF uygulamasıdır. Operatör mevcut kurulum/kaldırma scriptlerini UNC yollarıyla kaydeder; aynı tanımı daha sonra farklı hedeflerde çağırır. Paket Oluştur yeni bir MSI, EXE veya kurulum scripti üretmez. Mevcut scriptin nasıl çağrılacağını ve sonucunun nasıl doğrulanacağını kaydeder.

Uygulamada 26 yerleşik operasyon vardır. Dosya, registry, servis, görev ve süreç işlemleri de aynı Runner ve rapor altyapısını kullanır. Genel amaçlı çok adımlı operasyon reçetesi henüz uygulanmamıştır.

## 2. Taşınacak dosyalar ve sorumlulukları

Klasörün tamamını kopyalamak ve kökteki başlatıcıyı kullanmak en kolay dağıtım yöntemidir. Aşağıdaki yollar dağıtım köküne göredir.

| Dosya | Sorumluluk |
| --- | --- |
| YD_RemoteOps.App.bat | Alt klasördeki BAT başlatıcıya yönlendirir. |
| PsExec.exe | Paket adımını hedefte SYSTEM olarak çalıştırır. |
| RemoteOps.App/RemoteOps.App.bat | Çalışma klasörlerini ve başlatıcı logunu hazırlar; Windows PowerShell'i seçer. |
| RemoteOps.App/RemoteOps.App.ps1 | Ana WPF pencere, profiller, ayarlar, operasyon kataloğu, istek oluşturma ve süreç takibi. |
| RemoteOps.App/RemoteOps.PackageUi.ps1 | Paketlerim, Paket Oluştur ve çalıştırma özeti arayüzü. Runner tarafından yüklenmez. |
| RemoteOps.App/RemoteOps.Runner.ps1 | İstek doğrulama, operasyon dispatch, hedef döngüsü, paralel worker ve sonuç birleştirme. |
| RemoteOps.App/RemoteOps.Packages.ps1 | Paket şeması, katalog CRUD, revizyon, atomik kayıt, içe/dışa aktarma ve snapshot. |
| RemoteOps.App/RemoteOps.Deployment.ps1 | Kaynak erişimi probe, dağıtım kilidi, kur/kaldır/downgrade durum makinesi. |
| RemoteOps.App/RemoteOps.RunState.ps1 | İptal isteği, atomik hedef checkpoint, kesilen dağıtımın kısmi raporunu kurtarma. |
| RemoteOps.App/RemoteOps.Reports.ps1 | Sonuç normalizasyonu, CSV/HTML, ledger ve günlük rapor. |
| Modules/ApplicationWorkers.ps1 | Registry üzerinden uygulama tespiti, uygulama envanteri, sürüm karşılaştırma ve paket worker'ları. |
| Modules/FileOperations.ps1 | Yönetim paylaşımları üzerinden dosya işlemleri, korumalı yedek/silme, geri alma ve paket logları. |
| Modules/InventoryOperations.ps1 | CIM/DCOM uç nokta envanteri. |
| Modules/HealthOperations.ps1 | Ayrıntılı sağlık verisi ve tek Health.html raporu. |
| Modules/RegistryOperations.ps1 | HKLM string değerlerini okuma/değiştirme/silme ve geri alma kaydı. |
| Modules/ServiceTaskOperations.ps1 | CIM/DCOM servis, görev ve süreç işlemleri; yedek/geri alma. |
| docs/ | Kullanım, mimari, teknik el kitabı, inceleme, pilot ve geliştirme kayıtları. |
| tests/ | Geliştirici için yerel regresyon testleri; GUI'nin çalışması için gerekmez. |

Bu dağıtımda MD_Script.ps1, RemoteOps.ClmRunner.ps1 ve örnek Plugins klasörü bulunmaz. Mevcut GUI bunlara ihtiyaç duymaz. Eski testlerden ikisi kaldırılan dosyalara hâlâ referans verir; ayrıntı inceleme raporundadır. Eklenti keşif altyapısı korunmuştur fakat eklenti dağıtılmamaktadır.

## 3. Başlatma ve süreç zinciri

1. Kökteki BAT, RemoteOps.App altındaki BAT'ı çağırır.
2. Alt BAT, C:\Temp\YD_RemoteOps.App altında çalışma alanını hazırlar. 32 bit çağrı ortamında gerektiğinde Sysnative ile yerel Windows PowerShell'e geçer.
3. App.ps1 WPF penceresini açar; profilleri, ayarları ve kişisel paket kataloğunu okur.
4. Operatör çalıştırmayı onaylayınca Start-RemoteOpsRequest, girdileri ve seçilen paket snapshot'ını JSON'a çevirir. UTF-8 JSON Base64 olarak Runner'a aktarılır. Base64 şifreleme değildir. Parola bu istekte bulunmaz.
5. Ayrı powershell.exe Runner süreci hedefleri işler. Uygun operasyonlarda 1–10 worker ile paralel çalışabilir; izin verilmeyen operasyonlarda sıralı yürütme korunur.
6. GUI, 500 ms aralıklarla stdout, stderr ve progress JSON dosyalarını okuyarak ekranı yeniler. Ağ işinin tamamlanması için GUI thread'i bekletilmez.
7. Runner, sonuçları ve terminal hedef durumlarını birleştirir; HTML/CSV ve günlük ledger oluşturur. Sonuç HTML'i yerel tarayıcıda açılır.

Kodlanmış istek 22.000 karakteri aşarsa GUI isteği reddeder. Uzun hedef listeleri daha küçük çalışmalara bölünmelidir. Bu sınır hedef sayısına sabit bir üst sınır anlamına gelmez; paket tanımı ve diğer girdiler de boyuta dahildir.

## 4. Hesaplar: hangi işlem kimin yetkisiyle çalışır?

| Katman | Çalışma kimliği | Gereken erişim |
| --- | --- | --- |
| GUI | Uygulamayı açan Windows kullanıcısı | Kaynak dosyaları okuma; kişisel APPDATA ve çalışma alanına erişim. |
| Main Runner | Mevcut Windows oturum token'ı | Hedef yönetimi, WMI/DCOM ve SMB erişimi. Main profilindeki kayıtlı parola token değiştirmez. |
| Diğer profil Runner | Seçilen domain hesabı | Uygulama/modülleri okuma, veri/log klasörüne yazma, uzak yönetim ve kaynak erişimi. |
| Hedef paket | Hedef bilgisayarın SYSTEM hesabı | UNC paket klasörünü ve gereken bağımlılıkları okuyabilme. Domain ortamında ağ erişimi makine hesabı üzerinden değerlendirilebilir. |

Alternatif hesapta GUI, Start-Process -Credential -LoadUserProfile ile cmd.exe başlatır; cmd.exe Runner PowerShell'i çağırır. Parola SecureString olarak Windows süreç oluşturma API'sine verilir, komut satırına eklenmez. Ön kontrol seçilen hesabın yerel kod dosyalarını okuyabildiğini ve veri alanına yazabildiğini sınar; hedefteki bütün izinleri doğrulamaz.

Profil dosyasındaki domain/kullanıcı alanları düz metindir. Parola ConvertFrom-SecureString ile Windows DPAPI CurrentUser kapsamında korunur. domains.json başka Windows kullanıcısına veya bilgisayara taşınarak kullanılmamalıdır; profiller o bilgisayarda yeniden oluşturulur.

Operatörün UNC yolunu açabilmesi hedef SYSTEM'in de okuyabildiğini kanıtlamaz. Kaydedilmiş dağıtımda kaynak probe'u tam dosyayı hedef SYSTEM altında salt okunur açar. Kurulum scriptinin çağırdığı ek MSI, EXE, config veya alt klasörlerin tümünün erişimi bu tek dosya probe'u ile garanti edilmez; pilotta doğrulanır.

## 5. Uzak erişim yöntemleri

| İş | Yöntem | Açıklama |
| --- | --- | --- |
| Uygulama varlık/sürüm tespiti | WMI StdRegProv | HKLM uninstall kayıtları ve WOW6432Node görünümü taranır. Win32_Product kullanılmaz. |
| Dosyalar ve loglar | SMB yönetim paylaşımları | Örneğin C:\Temp hedef yolu \\PC\C$\Temp olur; farklı sürücüler ilgili yönetim paylaşımına çevrilir. |
| Envanter, servis, görev, süreç | CIM/DCOM | Hedef WMI/DCOM izinleri ve ağ erişimi gerekir. |
| Registry işlemleri | CIM StdRegProv | HKLM altında desteklenen string değerler; genel registry editörü değildir. |
| Paket çalıştırma | PsExec | Hedef SYSTEM, etkileşimsiz PowerShell wrapper ve paket exit code takibi. |

Standart operasyonlar PowerShell Remoting/WinRM oturumuna dayanmaz. Şirket ağında SMB yönetim paylaşımı, RPC/DCOM ve PsExec'in servis oluşturma/uzak çalıştırma izinleri ilgili yönteme göre sağlanmalıdır. Sadece ping sonucu bunların çalıştığını göstermez. Firewall, EDR ve uygulama kontrol politikaları şirket ekibi tarafından pilotta değerlendirilir; uygulama bunları değiştirmez.

## 6. Paket çalıştırma ayrıntısı

PsExec çağrısının temel biçimi aşağıdadır. EncodedCommand içindeki uzak PowerShell scripti UTF-16LE Base64'dür; GUI'den Runner'a giden UTF-8 JSON Base64 aktarımından farklıdır.

```text
PsExec.exe \\PC -s -accepteula -n 10 powershell.exe
  -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass
  -EncodedCommand <uzak wrapper>
```

- -s hedefte SYSTEM kullanır. -i kullanılmaz; interaktif masaüstü açılmaz. -d kullanılmaz; gerçek bitiş ve exit code beklenir.
- .bat/.cmd dosyaları cmd /d /v:off /c içinde UNC klasörüne pushd yapılıp call ile çalışır.
- .ps1 dosyaları etkileşimsiz PowerShell, .vbs dosyaları cscript //B ile çalışır.
- Wrapper kaynak klasör/dosya kontrolü yapar ve paket çıkış kodunu dışarı taşır. Paket kendi içinde sessiz ve gerçek exit code'u ileten bir script olmalıdır. Uygulama üçüncü taraf scriptin kendi başlattığı pencereleri veya çocuk süreçlerini denetleyemez.
- Yerel bağlantı bekleme parametresi 10 saniye; paket adımı üst bekleme süresi 2.700 saniye (45 dakika), kaynak probe'u 30 saniyedir.
- Uygulama tespit timeout parametresi 6 saniye; paket sonrası ilk bekleme 3 saniye, yeniden kontrol 6 deneme ve 10 saniye aralıklarla yapılır. Bunlar her çağrının toplam duvar saati süresini tek başına belirlemez.
- Çıkış kodu 0 normal; 3010 yeniden başlatma gereksinimi; 1641 yeniden başlatmanın başlatıldığına ilişkin paket bildirimidir. Diğer kodlar hata olarak değerlendirilir. Paket sonucu ayrıca seçilmiş tespit politikasına göre doğrulanır.

Timeout durumunda yerel PsExec sonlandırılır; uzaktaki paket devam edebilir. Çalıştırmanın gerçekleştiği fakat sonucunun bilinmediği hedefte Indeterminate kullanılır. Otomatik reboot, otomatik yeniden deneme veya eski paketi tekrar kurma yoktur.

## 7. Paket tanımı ve kişisel katalog

Katalog %APPDATA%\MDRemoteOps\Packages altında GUID adlı JSON dosyalarındadır. Yeni şema RemoteOps.Package/2'dir; /1 kayıtları yüklenirken anlamı korunarak normalize edilir, açık kaydetmede /2'ye yazılır. Katalog tek operatöre aittir; ortak UNC katalog yönetimi uygulanmamıştır.

| Alan | İşlev |
| --- | --- |
| Id, Revision | GUID ve pozitif revizyon; kaydetme sırasında eski revizyonla sessiz üzerine yazmayı önler. |
| Name, Category, Description | Görünen ad, filtre grubu ve kullanım açıklaması. |
| ApplicationKey | Uygulama ailesi anahtarı; aynı uygulamanın bütün sürümlerinde aynı tutulur. |
| TargetVersion / DowngradeVersion | Birbirinden bağımsız normal kurulum ve eski hedef sürümleri. DowngradeVersion sayısal karşılaştırılabilir olmalıdır. |
| Install / Uninstall / Downgrade | Bağımsız Enabled, PackagePath, PackageFile, SearchType, Application, RegistryKey, CheckMode alanları. |
| CollectLogs, DowngradeEnabled | Log toplama ve kontrollü downgrade seçimi. |
| CreatedAt, UpdatedAt | Oluşturma/güncelleme zamanları. |

PackagePath UNC klasörüdür; PackageFile yalnızca dosya adıdır ve desteklenen uzantılardan biri olmalıdır. Install, Uninstall ve Downgrade aynı kimliğe zorlanmaz; sürümler arasında ProductID değişebilir. DisplayName exact tam ad, DisplayName contains içerme eşleşmesi, ProductID uninstall kayıt kimliği üzerinden aramadır. İsteğe bağlı RegistryKey yanlış bir kayıtla eşleşmeyi engellemek için tam anahtar sınırı koyar. Belirsiz çoklu eşleşme değişiklikten önce çözülmelidir.

CheckMode değerleri Version controlled, Presence only ve Trigger without checks'tir. Sonuncusu uygulama durumunu kanıtlamaz; yalnızca tetikleme sonucunu verir. Downgrade kontrollü tespit ve sürüm karşılaştırması ister.

Kaydetme atomik geçici dosya ve File.Replace/Move ile yapılır. Katalog .json.lock dosyasını FileShare.None açarak aynı kayıt üzerinde yerel yazma kilidi alır. Beklenen revizyon kontrol edilir; bozuk kayıt veya daha yeni revizyon sessizce ezilmez. Boş kilit dosyasının kalması aktif kilit anlamına gelmez; kilit açık dosya handle'ıdır.

Kopyalama yeni GUID/revizyon 1 üretir ve aile anahtarını korur. Dışa aktarım RemoteOps.PackageExport/2 zarfını kullanır; içe aktarım /1 ve /2 kabul eder. Eski uygulamanın yeni alanları görmezden gelip yanlış kurulum çalıştırmaması için kayıt ve zarf sürümü yükseltilmiştir. Çakışmalar yazmadan önce önizlenir; Atla/Kopyala/Değiştir politikası açıkça seçilir. Bütün dosyalar için tek bir transaction garantisi yoktur; yazma hataları raporlanır.

Paket tanımı, export ve request snapshot'ı parola, hedef listesi veya çalıştırma onayı saklamaz. Runner kişisel katalog dosyasını tekrar açmaz; Values.PackageDefinition içindeki doğrulanmış snapshot'ı kullanır. Snapshot ayrıca rapor klasöründe PackageDefinition.json olarak saklanır. Çalışma sırasında katalog düzenlemek başlamış işlemi değiştirmez.

## 8. Kurulum ve kaldırma kararları

Kontrollü Kur işlemi önce uygulamayı arar. Version controlled modunda hedef sürüm veya daha yeni bir sürüm zaten kuruluysa tekrar kurulum yapılmaz. Kurulum gerektiğinde kaynak doğrulanır, paket çalıştırılır ve yeni uygulama tespiti yapılır. Normal kurulum AtLeast politikası kullanır: son sürüm hedefe eşit veya daha yeni olabilir.

Kontrollü Kaldır işlemi kayıtlı kaldırma kimliğine göre tespit yapar. Uygulama yoksa atlar. Paket bittikten sonra aynı kimliğin yokluğu sınanır. Presence only sürüm eşitliği kontrol etmez. Kontrolsüz tetiklemede uygulama varlığı/sürümü doğrulanmış gibi rapor verilmez.

## 9. Downgrade durum makinesi

1. Hedef için aile kilidi al. Yönetim erişimini dene. Kaldırma kimliğini tespit et; yoksa ayrı Downgrade kimliği mevcut eski sürümü açıklamak için kontrol edilir.
2. Mevcut sürümü DowngradeVersion ile karşılaştır. Yalnızca daha yeni sürüm ve doğru kaldırma kimliği ile değişiklik yapılır.
3. Hem kaldırma hem ayrı eski sürüm dosyasını seçilen hesap ve hedef SYSTEM erişimi açısından kaldırmadan önce doğrula.
4. Kaldırma paketini çalıştır. Hata, belirsiz sonuç veya yeniden başlatma gereksiniminde zinciri durdur.
5. Kaldırma kimliği ile yokluğu doğrula. Uygulama hâlâ varsa kurulum başlatma.
6. Downgrade paketini Install/Exact adımı olarak çalıştır. Yeni tespit Downgrade kimliğiyle yapılır; eski tespit nesnesi tekrar kullanılmaz.
7. Son sürümün DowngradeVersion ile tam eşit olduğunu doğrula ve hedefin terminal sonucunu yaz.

| Başlangıç durumu | Davranış |
| --- | --- |
| Daha yeni sürüm, doğru kaldırma kimliği | Kaynaklar doğrulanır; kaldırma, yokluk, kurulum, tam sürüm kontrolü. |
| Hedef sürüm zaten kurulu | Skipped. |
| Hedeften daha eski sürüm | Skipped; Kur kullanılmalı. |
| Uygulama yok | Skipped; Kur kullanılmalı. |
| Kimlik belirsiz, erişilemiyor, sürüm karşılaştırılamıyor | Değişiklikten önce Error. |
| Kaldırma 3010/1641 | RebootRequired; kurulum ve otomatik reboot yapılmaz. |
| Kaldırma tamamlandı, kurulum başarısız | Uygulamanın kaldırıldığı adım kaydı korunur; otomatik geri kurulum yapılmaz. |

Sürüm karşılaştırıcısı sayısal sürümlerde 2.0 ile 2.0.0 gibi eşdeğerleri tanır. Desteklenmeyen metinsel sürümlerde zorla downgrade kararı üretmez. Downgrade genel geri alınabilir transaction değildir; pilotta kurtarma paketinin sorumlusu ayrıca belirlenir.

## 10. Paralellik ve çakışma önleme

GUI ve Runner aynı ParallelSafeOperations listesini kullanır. ApplicationCheck, ApplicationInventory, PackageTrigger, PackageDeployment, EndpointInventory, HealthCheck, RegistryRead, ServiceList, ProcessQuery, ScheduledTaskList için hedefler paralel işlenebilir. Diğer mutasyonlar sıralı kalır.

Coordinator her worker'a tek hedef, kendi stdout/stderr dosyaları ve XML sonuç yolu verir. Tamamlanan worker sonuçları çalışma kimliği altında birleştirilir. Worker başlatma hatası ve checkpoint yokluğu Error olarak tanılanır; iptal gibi gösterilmez.

DeploymentLocks altında hedef adı + ApplicationKey için SHA-256 adlı .lock dosyası FileShare.None açılır. Aynı veri kökünü kullanan koordinatörde çakışan dağıtım engellenir. Farklı operatör bilgisayarları arasında ortak kilit bulunmaz; dağıtım takvimi ekip tarafından koordine edilir.

## 11. Durdurma, checkpoint ve kısmi sonuç

Kaydedilmiş dağıtımda Durdur iptal marker'ı yazar. Yeni hedef veya yeni adım başlamaz; aktif paket adımının bitişi beklenir. Zorla durdur yerel süreç ağacını taskkill /T /F ile kapatır. Diğer operasyonların Durdur davranışı da yerel süreç ağacını sonlandırmadır; aynı kısmi rapor güvencesi verilmez.

RunState, hedef aşamasını ve terminal sonucu atomik checkpoint dosyalarına yazar. run.json çalışma kimliği, rapor yolu, hedefler, gerçek çalışma kimliği, snapshot ve eylemi içerir. GUI, süreç kapandığında Complete-RemoteOpsInterruptedDeployment ile mevcut checkpoint'lerden kısmi rapor ve ledger üretmeyi dener.

Terminal checkpoint varsa sonucu korunur. Başlamamış iptal edilen hedef Cancelled olur. Mutasyon başladıysa ve sonuç kanıtlanamıyorsa Indeterminate olur. Tam GUI çökmesi veya metadata kaybından sonra otomatik yeniden açıp devam etme/resume garantisi yoktur. Kesilen uzak iş doğrulanmadan tekrar başlatılmaz.

## 12. Sonuç sözlüğü ve rapor anlamı

| Durum | Anlamı ve operatör eylemi |
| --- | --- |
| Success | Operasyonun tanımlı başarı koşulu sağlandı; kontrolsüz tetikleme uygulama durumunu doğrulamaz. |
| Skipped | İşlem bilinçli olarak uygulanmadı; neden okunmalı. Dosya karşılaştırmada farklı içerik de nötr Skipped olabilir. |
| Error | Bilinen hata veya doğrulanmış uygunsuz durum; teknik/adım detayını incele. |
| Unreachable | Erişilemeyen hedef olarak sınıflandırıldı; her bağlantı hatası bu sınıfa düşmeyebilir. |
| Cancelled | İptal nedeniyle tamamlanmamış/başlatılmamış işlem. |
| Indeterminate | Uzak mutasyonun son durumu bilinmiyor; hedefte varlık/sürüm ve çalışan kurulum kontrol edilmeli. |
| RebootRequired | Zincir reboot gereksinimi nedeniyle durdu; planlı yeniden başlatma sonrasında tekrar tespit yap. |

Completed ilerleme sayısı başarılı hedef sayısı değildir. Paket sonuç HTML ana tablosu terminal Result satırını hedef özeti olarak gösterir; son yürütme adımının ExitCode/log alanları bir kopya üzerinde tamamlanır. Özgün CSV/checkpoint satırları değişmez. Eşleşen adımlar açılır Adım ayrıntıları bölümündedir; terminal kaydı oluşmamış hata hedefleri ana tabloda tutulur. Ledger hedef başına bir terminal kayıt tutar; downgrade'in kaldırma ve kurulum adımları iki başarılı hedef gibi sayılmaz. Günlük Rapor paket kimliği/adı ve eyleme göre hedef denemelerini ayrıca gruplar; başarı, atlama, dikkat ve iptal sayıları hem GUI hem günlük HTML'de görünür. Aynı adlı farklı kayıt kimlikleri ve farklı eylemler ayrı kalır. Geçmişte paket metadata'sı olmayan kayıtlar genel toplamlarda korunur.

## 13. Veri ve log yolları

Dağıtım klasörü yeniden adlandırılsa da veri kökü C:\Temp\YD_RemoteOps.App olarak kalır. Kullanıcı verileri ile çalışma çıktıları farklı alanlardadır.

| Yol | İçerik |
| --- | --- |
| %APPDATA%\MDRemoteOps\domains.json | Profil bilgileri ve DPAPI parola. |
| %APPDATA%\MDRemoteOps\settings.json | Operatör ayarları. |
| %APPDATA%\MDRemoteOps\Packages\<GUID>.json | Kişisel paket tanımları. |
| C:\Temp\YD_RemoteOps.App\Logs | Başlatıcı ve uygulama logları. |
| Logs\Operations\<Operasyon>\<OperationID> | Results.csv/html, Activity.csv/html, RemoteOps.log, varsa PackageDefinition.json. |
| Aynı çalışma altındaki Detail | Modüllerin ara sonuç dosyaları. |
| Aynı çalışma altındaki Workers | Paralel worker stdout/stderr ve XML sonuçları. |
| Logs\Operations\<Operasyon> altında GUID dosyaları | GUI stdout/stderr, progress JSON, .cancel ve .state metadata/checkpoint alanı. |
| Logs\Reports\Ledger\<OperationID>.csv | Günlük rapora beslenen terminal hedef kayıtları. |
| Logs\Reports\Daily_<yyyy-MM-dd>.html | Rapor sekmesinden dışarı açılan günlük HTML. |
| PulledLogs\<PC>\<AdımID_Operasyon> | Hedeften toplanmış paket logları; downgrade adımları ayrıdır. |
| PulledFiles\<PC> | Hedeften çekilmiş dosyalar. |
| DeleteBackups | Yedekli silme işleminin yedekleri ve kayıtları. |
| FileRollbacks | Dosya taşıma/değiştirme geri alma manifest ve yedekleri. |
| RegistryRollback | Registry eski değer/yokluk bilgisi ve manifest. |
| ServiceTaskRollbacks | Servis/görev eski durumları ve silinen görev XML'leri. |
| DeploymentLocks | Yerel hedef/aile kilit dosyaları. |

HealthCheck tek Health.html içinde hedef listesini toplar. Raporlar yerelde oluşturulur; uygulama buluta gönderim yapmaz. Log/raporlar bilgisayar adları, yollar ve operasyon girdileri içerebilir; şirketin saklama ve erişim kuralları uygulanır. Yedekler ve manifestler birlikte tutulmalıdır. FileOperations başlatıldığında DeleteBackups altında LastWriteTime değeri 7 günden eski yedek klasörlerini temizlemeyi dener; bu alan uzun süreli arşiv değildir. Diğer log/yedek alanları için genel otomatik arşivleme politikası bulunmaz.

Paket log toplama C:\Windows\Temp ve alt klasörlerinde oluşturulma veya değişiklik zamanı son 10 dakika içinde olan .log/.txt dosyalarını alır; yalnızca seçilen pakete ait logları bulma garantisi yoktur. Ayrı hedefte temizleme ayarı daha dar kapsamlıdır: sadece doğrudan Temp içindeki, başarıyla çekilmiş, SHA-256 ile değişmediği doğrulanmış ve geçerli kullanıcı adıyla eşleşen dosyalar; sistem logları/reparse noktaları korunur. Paket normal bitmemişse temizleme yapılmaz. Eşleşme sayısı 50'yi aşarsa temizleme reddedilir. İlk pilotta temizleme kapalı tutulabilir.

## 14. Yerleşik operasyonların haritası

| Teknik operasyon | İşlev / temel girdiler | Değişiklik ve geri alma |
| --- | --- | --- |
| ApplicationCheck | SearchType, SearchValue, RegistryKey ile uygulama tespiti. | Salt okunur. |
| ApplicationInventory | Kurulu uygulama kayıtları. | Salt okunur. |
| PackageTrigger | Manuel Install/Uninstall, UNC script, kimlik, sürüm, kontrol modu. | TRIGGER; kaydedilmiş downgrade akışı değildir. |
| PackageDeployment | Paket snapshot'ından Install/Uninstall/Downgrade. | TRIGGER veya DOWNGRADE; checkpoint ve aile kilidi. |
| FilePull | Hedefteki Path yolunu çek. | Hedefte değişiklik yok. |
| FileDelete | Path için korumalı yedekle/sil. | DELETE; DeleteBackups üzerinden restore. |
| FilePush | LocalPath içeriğini Path hedefine gönder. | Overwrite seçimi; genel transaction garantisi yok. |
| FileCompare | Yerel referans ile uzak dosyayı karşılaştır. | Salt okunur; fark detayda. |
| FileBrowser | Tam dosya yoluyla Pull/Move/Replace. | MOVE/REPLACE; manifest üzerinden FileRollback. |
| FileRestore | Silme yedeğini geri yükle. | RESTORE; hedef ve yedek kapsamını kontrol et. |
| FileRollback | Taşıma/değiştirme geri alma. | ROLLBACK; seçili hedefe daraltılmış manifest. |
| EndpointInventory | İşletim sistemi/donanım envanteri. | Salt okunur. |
| HealthCheck | Ayrıntılı sağlık; SkipApps ile uygulama taramasını atlama. | Salt okunur; tek HTML. |
| RegistryRead | HKLM RegistryPath / ValueName. | Salt okunur. |
| RegistryEdit | String Value yazma. | EDIT; eski varlık/değer manifestte. |
| RegistryDelete | Registry değerini silme. | DELETE; eski varlık/değer manifestte. |
| RegistryRollback | Registry manifestini geri alma. | ROLLBACK. |
| ServiceList | Servis adı/görünen ad filtresi. | Salt okunur. |
| ServiceControl | ServiceName için Start/Stop/Restart. | Eylemin büyük harfli adı; eski durum kaydı. |
| ServiceStartup | Automatic/Manual/Disabled. | EDIT; eski başlangıç türü kaydı. |
| ServiceTaskRollback | Servis/görev manifestini geri alma. | ROLLBACK. |
| ScheduledTaskList | Görev filtresi ile liste. | Salt okunur. |
| ScheduledTaskDelete | Tam görev adı ve gerekiyorsa TaskPath. | DELETE; XML ve CSV önce yazılır. |
| ScheduledTaskAction | Run/Enable/Disable. | Eylemin büyük harfli adı; çalışmış görevi geri almak mümkün değildir. |
| ProcessQuery | Ad/PID; boşsa süreç listesi. | Salt okunur. |
| ProcessKill | Tam süreç adı veya PID. | KILL; kritik süreçler korunur; tekrar başlatma geri alması yok. |

## 15. Koruma ve geri alma sınırları

Dosya silmede korunan kökler, geniş wildcard ve reparse point kontrolleri vardır. Silmeden önce envanter/hash ve robocopy yedeği doğrulanır; robocopy >=8 hata kabul edilir. Kaynak değişmişse silme yapılmaz; silme sonrası yokluk kontrol edilir. FileRestore ve FileRollback farklı türde yedek/manifestleri kullanır.

Registry işlemleri HKLM ve REG_SZ string kapsamındadır. Eski değer veya değerin önceden bulunmadığı bilgisi değişiklikten önce kaydedilir. Servis yöntemlerinin dönüş kodu kontrol edilir; yalnızca komut çağrıldı diye başarı yazılmaz.

Görev silmede tam ad/yol belirsizliği çözülür, XML ve manifest dayanıklı biçimde yazılır. Password logon kullanan görevler silinmez; XML parola içermez ve geri yükleme garantisi veremez. Geri almada mevcut görev ezilmez ve önceden çalışan görev otomatik tekrar çalıştırılmaz.

ProcessKill LSASS, SYSTEM, SVCHOST gibi kritik süreçleri korur. Süreç öldürme kaydı denetim kaydıdır; çalışmakta olan süreç durumunu geri getiren bir yedek değildir. Yazılım kaldırma/downgrade de otomatik yazılım rollback'i sağlamaz.

## 16. Eski modül uyarlama ve geliştirme noktaları

Ortak izleme tablosu artık bütün operasyonları gösterir. Progress JSON Targets dizisinde ComputerName, Stage ve Outcome taşır; sıralı/paralel koordinatör hedefin bekleme/çalışma/bitiş durumunu günceller. GUI son snapshot'ı çalışma modelinde saklar; progress dosyası silinince sonuç kaybolmaz. Satırlar ProgressPath ile ayrı çalışma gruplarında birleştirilir. Kaydedilmiş dağıtım için ayrıntılı checkpoint okuma korunur; diğer işlerde durdurma doğrulanmış başarı gibi sunulmaz.

Manuel paket kaydetme kısayolunda Get-OperationValues yalnız Panel alan satırlarını okur; düğme gibi Children taşımayan kontroller atlanır. Kısayol editörü açar; ad ve kategori operatör tarafından tamamlanıp kaydedilir.

Runner, ApplicationWorkers.ps1 içindeki RegistryCheckScript, InstalledApplicationInventoryScript, PackageScript scriptblock'larını AST ile adlarına göre çıkartır. Compare-ApplicationVersion gibi gereken fonksiyonları ayrıca alır. Bu isimler ve parametre sırası uyumluluk sözleşmesidir; gelişi güzel değiştirilmemelidir.

Menü tabanlı diğer modüller için Runner Read-Host yerine FIFO PromptAnswers kuyruğu kullanır. Write-Host konsol menülerini filtreler ve aktivite/teknik çıktıyı toplar. Start-Process üzerinden açılacak HTML/CSV yolları çalışma raporuna yönlendirilir. Menü numarası veya soru sırası değişirse Runner'ın cevap sırası ve ilgili testler birlikte güncellenir.

Yeni yerleşik operasyon için App.ps1 OperationCatalog, Assert-OperationInputs, Runner switch, Reports.ps1 metadata ve gerekiyorsa iki taraftaki ParallelSafeOperations güncellenir. GUI ana XAML x:Name kontrolleri dosyanın sonundaki bağlama listesindedir; PackageUi kendi kontrol sözlüğünü kullanır.

Türkçe literal içeren PowerShell 5.1 kaynakları UTF-8 BOM ile korunmalıdır. Kültüre duyarlı dosya adı temizliğinde kullanılan -creplace kasıtlıdır. Katalog ve log yazımları paralel worker paylaşımını gözetmelidir; mevcut log append helper'ı write-only FileStream ve sınırlı retry kullanır.

Plugins klasörü sonradan eklenebilir: manifest script yolu klasör içinde göreli olmalı, operasyon adı benzersiz olmalı, script -Request ve -Context almalıdır. Çağrı hedef başına yapılır. ParallelSafe ancak paylaşılan dosyalara çakışan yazma yapmayan eklentilerde açılır. Eklenti seçilen hesabın yetkisiyle çalışan güvenilir yerel koddur. Bu dağıtımda örnek eklenti yoktur.

## 17. Yerel doğrulama ve şirket pilotu

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\RemoteOps.App\RemoteOps.Runner.ps1 -ValidateHostWorkers
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\tests\RemoteOps.PackageLibraryUi.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\tests\RemoteOps.Reports.Tests.ps1
```

Kaynak parse kontrolü, şema/durum makinesi/mock testleri ve WPF testleri yerelde uygulanabilir. Gerçek domain hesabı, hedef SYSTEM'in UNC erişimi, EDR/PsExec davranışı, gerçek kurulum çıkış kodları ve uygulamanın doğru registry kaydı şirket pilotunda kanıtlanmalıdır. Tek domain kullanımında da Main ve aynı domaindeki alternatif yönetici hesapları kullanılabilir. CLM domain sayısı değildir; AppLocker/WDAC gibi yerel uygulama kontrol politikalarıyla ilgili PowerShell dil kısıtıdır. CLM runner bu dağıtımda bulunmaz ve geliştirme kapsamında değildir. FullLanguage Windows PowerShell 5.1 çalışma varsayımıdır; Constrained Language Mode uyumluluğu doğrulanmamıştır.

Güncel çalıştırma sonuçları [inceleme raporunda](INCELEME_RAPORU.md), pilot kayıt tablosu [pilot kontrolünde](PAKET_YONETIMI_PILOT_KONTROLU.md), ekran adımları [kullanım kılavuzunda](KULLANIM_KILAVUZU.md) bulunur.

## 18. Sorun giderme tablosu

| Belirti | Kontrol ve sonraki adım |
| --- | --- |
| GUI açılmıyor | Başlatıcı Logs çıktısını, Windows PowerShell 5.1/STA ve PresentationFramework yüklenmesini incele. |
| Alternatif profil preflight hatası | Runner/modül/PsExec okuma ve C:\Temp veri alanı yazma erişimini seçilen hesapla kontrol et. |
| UNC operatörde açılıyor, paket probe hata | Hedef SYSTEM/makine hesabı paylaşım ve NTFS izinleri; tam dosya yolu ve ağ erişimi. |
| Uygulama yok/çoklu eşleşme | Yerleşik ApplicationInventory ile gerçek DisplayName, ProductID, sürüm ve registry anahtarını karşılaştır. |
| Paket 0 döndü fakat postcheck hata | Script exit aktarımı, doğru tespit kimliği ve gecikmeli uninstall kayıt oluşumunu kontrol et. |
| Indeterminate / timeout / zorla durdur | Hedefte kurulum süreci, uygulama varlığı/sürümü ve logları kontrol et; tekrar çalıştırmadan önce sonucu netleştir. |
| RebootRequired | Paket kodu ve adımı incele; şirket prosedürüyle reboot sonrası tespiti yeniden yap. |
| Rapor bulunamıyor | OperationID klasörü, Results/Activity ve stderr; HTML tarayıcı açma hatası işlem başarısını tek başına değiştirmez. |
| Paket kayıt çakışması | En yeni revizyonu yeniden aç; kilit dosyasını silmek yerine aktif başka düzenlemeyi kontrol et. |
| Downgrade kaldırdı fakat kuramadı | Kaldırma/kurulum adım kayıtlarını sakla; belirlenen kurtarma paketini sorumlu ekiple uygula. |

## 19. Doküman ve ekran görüntüsü üretimi

PDF üreticisi docs/tools/build_documents.py; WPF görselleri docs/tools/capture_documentation.ps1 ve paket UI testiyle hazırlanır. Örnek veriler canlı şirket testi kanıtı değildir. Ekran/alan değişince kılavuz, teknik sözleşme ve pilot birlikte güncellenir; operasyon adları ve veri yolları kodla karşılaştırılır.

## 20. Kapsamlı denetim sonrası çalışma sözleşmesi

Registry/servis mutasyonundan önce eski durum atomik CSV manifestine yazılır; yedek yazımı başarısızsa mutasyon yapılmaz. Paket metin alanları JSON string olmalıdır. ProductID tüm eşleşmeleri tarar; belirsiz kayıtlar tam anahtarla ayrıştırılır. Kurtarma checkpoint'leri çalışma/paket kimliğiyle sınırlandırılır; beklenmedik Runner çıkışında bilinen sonuçlar korunur, kalanlar belirsiz/hata olarak tamamlanır. Son ilerleme özeti güncel hedef durumundan hesaplanır. ISO bitiş zamanı ledger'da korunur. Main silmek başka bir hesabı Main yapmaz. Ayrıntı inceleme raporundadır.


## 21. Çalıştırma seçimi ve rapor bağlantısı

GUI MonitorRuns ve RunTargetRows oturum koleksiyonlarını benzersiz ProgressPath ile tutar. Yeni kimlik seçimi son işe taşır; mevcut iş güncellemesi kullanıcının seçimini korur. Tüm çalışmalar görünümü RunLabel üzerinden WPF CollectionView gruplaması kullanır. Yeni seçimde yalnızca ilgili ilerleme kartı ve hedefler görünür. Aynı bilgisayarın farklı çalıştırmaları birleştirilmez. Seçili hedeflerin durum sayıları ayrıca gösterilir; genel aktif iş sayısı tüm işleri kapsar.

Koordinatör Runner, ProgressPath kapsam doğrulamasından sonra ProgressPath.reportroot dosyasına o çalışmanın rapor klasörünü yazar; worker süreçleri bu bağlantıyı değiştirmez. GUI sadece Logs\Operations altındaki klasörleri kabul eder. Results.html, Health.html, Error.html önceliklidir; diğer raporlar ve Activity.html geri dönüş olarak kullanılır. Rapor hazır değilse veya tüm çalışmalar seçiliyse rapor düğmesi pasiftir. Bu dosya ilerleme JSON'undan ayrıdır; JSON temizlense bile aynı oturumda rapor yeniden açılabilir. Durdurma düğmeleri tüm aktif işler için çalışmaya devam eder.


## 22. Paket on kontrol hata ayrintisi

Install/Uninstall/Downgrade on kontrolunde Hata durumundaki gercek ErrorDetail terminal sonucuna aktarilir. Genel uygulama kimligi mesaji baglanti veya yetki hatasini gizlemez. CokluEslesme ayri kimlik secimi aciklamasi kullanir. Bu hatalarda paket veya kaynak kontrolu baslatilmaz. Sonuc Error olarak kalir: bilgisayarin kapali olmasi, RPC/guvenlik duvari veya yetki sorunu yalnizca genel Hata statusunden kesin ayirt edilemez. RemoteOps.DetectionErrors.Tests.ps1 RPC, erisim reddi ve coklu eslesmeyi uc eylemde sinar.


## 23. Yönetim bağlantısı kapısı ve log gezinme

Test-RemoteOpsTargetAccess varsayılanında System.Management.ManagementScope.Connect ile root\default üzerinde salt okunur bağlantı açar. v11 Runner, Invoke-TargetBatch içinde ortak Test-RemoteOpsOperationAccess kapısını kullanır; bu kapı modül veya paket çağrısından önce çalışır. Paket motorunun isteğe bağlı CheckAccess callback API'si korunur; normal GUI akışında aynı kontrol ikinci kez yapılmaz. Bilinen RPC/ağ/taşıma HRESULT'ları Unreachable, DCOM/provider access denied ve oturum açma reddi AccessDenied, diğer kodlar Failed olur. AccessDenied ve Failed terminal Error'dur. Yan etkisi başlamış bir paketteki sonraki bağlantı kaybı eski Indeterminate güvenlik davranışını korur. Ping kullanılmaz. [Microsoft WMI bağlantı ve erişim rehberi](https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/scenario-guide-troubleshoot-wmi-connectivity-access-issues) ve [WMI hata sabitleri](https://learn.microsoft.com/en-us/windows/win32/api/wbemdisp/ne-wbemdisp-wbemerrorenum) ayrımı açıklar.

Get-AORecentLogs isteğe bağlı CollectionGroup alır. Paket worker LogCollectionGroup ile bu değeri iletir; Runner kendi RunReportRoot klasör adını kullanır. Yeni paket logları PulledLogs\RunID\Computer\StepOperation düzenindedir; diğer çağrılar için eski düzen korunur. Log temizleme CollectedRoot üzerinden aynı güvenlik akışını sürdürür.

GUI Get-RemoteOpsRunLogInfo, çalışma .reportroot bağlantısını Logs\Operations kapsamında doğrular ve aynı RunID'nin PulledLogs alt klasörünü bulur. Bilgisayar adı ve klasör kapsamı kontrol edilir. Dosya bulunmadan açma etkinleşmez. Get-RemoteOpsRunCheckpoints içindeki adım LogCollectionStatus bilgisi kayıtlı paket satırına taşınır; iki adımda kısmi başarı/hata saklanır. Open-RemoteOpsLogFolder yalnızca yerel PulledLogs altındaki mevcut klasörleri açar. Gerçek WPF satır düğmesi tıklaması routed-event testiyle sınanır.


## 24. Üç bağımsız paket tanımı ve uyumluluk

RemoteOps.Package/2 tanımında Install normal kurulum, Uninstall kaldırma, Downgrade ayrı eski sürüm kurulum paketidir. Downgrade.Enabled ve DowngradeEnabled birlikte etkinleşir. UI üçüncü kartı isteğe bağlı açar, kendi DowngradeVersion/UNC/script/arama kimliği/tam registry anahtarını kaydeder; bu adımın kontrol modu Version controlled ve çalıştırma politikası Exact'tir. Downgrade için Install.Enabled gerekli değildir; Uninstall ve Downgrade kontrollü ve etkin olmalıdır.

Copy-RemoteOpsPackageDefinition /1 kayıtlarını /2'ye normalize eder. Eski downgrade etkinse eski Install nesnesinin alanları bağımsız kopyalanır ve eski TargetVersion -> DowngradeVersion aktarılır. Normal Install/TargetVersion korunur. Okuma diske yazmaz; kaydetme beklenen revizyon kilidiyle yükseltir. /2 kaydı eski uygulamada şema reddi üretir; yeni biçim eski okuyucunun normal Install'ı yanlış downgrade paketi olarak çalıştırmasını önler.

Deployment efektif hedef sürümünü eyleme göre seçer; downgrade fallback tespiti, iki kaynak kontrolü, kurulum ve son tespit için yalnızca Downgrade nesnesini kullanır. Runner kaynak preflight'ı Uninstall+Downgrade dosyalarını kontrol eder ve worker TargetInstallVersion değerine DowngradeVersion gönderir. Sonuç/checkpoint satırlarının TargetVersion alanı çalıştırılan eylemin hedefidir. Snapshot, kopya ve import/export üçüncü alanı taşır. IndependentDowngrade testi normal 5.0/eski 2.0 ayrımını, legacy okuma/kaydetme/import'u ve preflight kaynak seçimini doğrular.


## 25. v10 operasyon ipuçları, çekim yolu ve canlı doğrulama

Get-RemoteOpsOperationExample seçilen operasyon ve alan anahtarına göre açıklama üretir; Add-OperationField girdi hücresinin altında TextBlock gösterir. Get-OperationValues yalnızca gerçek giriş kontrollerini okur; örnek metinleri girdi olmaz. Kullanıcı değerleri ve onayları doldurulmaz.

FileOperations Get-AOFilePullRoot isteğe bağlı PullGroup ile PulledFiles/RunID kökü üretir. Runner kendi RunReportRoot adını FilePull ve FileBrowser çağrılarına iletir. FileBrowser artık sonuç satırlarında LokalHedefPath bilgisini ve CSV sonucunu döndürür. Get-RemoteOpsPulledFileInfo .reportroot bağını ve yerel kapsamı kontrol eder; çalışma/istemci altında tek dosya varsa tam yol, çok dosyada klasör döndürür. Show-RemoteOpsPulledFile yalnızca PulledFiles altında mevcut yola izin verir; tek dosyada explorer /select kullanır. Böylece indirilen .ps1/.exe gibi dosyalar varsayılan uygulama ile yanlışlıkla çalıştırılmaz.

Türkçe kültür kaynaklı ASCII I reddi canlı testte yakalandı. Açık A-Z/a-z aralıklarında case-sensitive regex kullanılır; Unicode veya yol geçişine izin verilmez. DCOM ScheduledTasks silme çağrısında explicit -Confirm kullanılmaz; daha önce alınan kullanıcı onayı ve kalıcı yedek sonrası yerel ConfirmPreference=None kapsamı uygulanır.

45 otomatik test dosyası dışında tests/Invoke-RemoteOpsLocalLiveTest.ps1, açık -RunLive ve yönetici token ile kendi GUID kaynaklarını oluşturup gerçek modül fonksiyonlarını çalıştırır. Canlı son tur 18/18 geçti ve altı cleanup kontrolü başarılıdır. [Ayrıntılı canlı rapor](CANLI_TEST_RAPORU.md) test sınırlarını ve ilk tur düzeltmelerini kaydeder. Sandbox dışındaki gerçek servis/görev/kayıtlar test hedefi değildir.


## 26. v11 ortak erişim kapısı ve sarı sonuçlar

Invoke-TargetBatch, sıralı çalıştırmada ve paralel worker içinde aynı erişim kapısını çağırır. File* işlemleri SMB admin$ okumayı; Registry* işlemleri root\default WMI/DCOM bağlantısını; diğer yönetim işlemleri root\cimv2 bağlantısını sınar. Kontrollü paketler SMB ve root\default kullanır; kontrolsüz kayıtlı scriptler ve kimliksiz doğrudan tetiklemeler SMB ile sınırlıdır. ICMP kullanılmaz. Eklentilerin manifest/script sınırları ve bilinmeyen operasyonlar hedef bağlantısından önce doğrulanır. Özel eklentiler varsayılan yönetim bağlantı kontrolünü kullanır.

SMB'nin tamamı aynı kimlikle açılan gizli PowerShell alt sürecinde salt okunur olarak çalışır. Alt süreç için 6 saniye bekleme sınırı vardır; süre aşımında yalnızca bu süreç sonlandırılır. WMI bağlantısı mevcut ConnectionOptions.Timeout=6 mekanizmasını kullanır. Yanıt vermeyen yönetim sağlayıcısına ait işletim sistemi gecikmeleri SMB alt süreç sınırıyla aynı mekanizma değildir.

Bilinen ağ/RPC/bağlantı kodları Unreachable, erişim reddi AccessDenied, diğerleri Failed olur. Erişilemeyen hedefte modül, tespit, kaynak çalıştırma veya mutasyon çağrılmaz. Kayıtlı paket adı/kimliği/revizyonu/eylemi ve orijinal tanı hem sonuçta hem durable checkpoint'te korunur. Yetki ve bilinmeyen hatalar Error'dur. İşlem başladıktan sonraki hatalar körlemesine sarıya çevrilmez; paket Indeterminate güvenliği korunur.

Ledger ham Skipped ve Unreachable sayılarını ayrı tutar. Günlük raporun Neutral alanı ikisini toplar; Problems yalnızca Error/Indeterminate/RebootRequired içerir. WPF, HTML, kategori ve paket kırılımları aynı hesabı kullanır. Eski kayıt dosyaları yeniden yazılmaz. Kontrolsüz script davranışı UncheckedScript testinde sürüm ve kimlik sorgusu çağrılmadan doğrulanır.

v11 salt okunur yerel bağlantı sonucu docs/live-test-v11/ACCESS_LIVE_TEST.json içindedir. Önceki 18 gerçek mutasyon/geri alma testi v10 tarihsel kanıtıdır; bu sürümde tekrar çalıştırılmış gibi sunulmaz. Normal *.Tests.ps1 turu canlı test scriptlerini otomatik çağırmaz.
