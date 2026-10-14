# RemoteOps kapsamlı test ve inceleme raporu

14 Ekim 2026 · YD_RemoteOps.App_v11 · Yerel güvenilirlik denetimi

Bu denetim mevcut uygulama, altı modül, paket kataloğu, dağıtım motoru, rapor ve WPF akışlarını kapsar. Gerçek şirket uç noktalarına bağlanılmadı. Otomatik regresyonlarda izole fixture/mock verileri kullanıldı; ayrıca bu bilgisayarda gerçek CIM/DCOM, SMB, dosya, registry, servis, görev ve süreç çağrılarıyla 18 güvenli canlı senaryo doğrulandı. Paket kurulumları ve şirket ağı kabul testi bu yerel canlı turun kapsamında değildir. Gerçek Windows PowerShell 5.1 süreçleri, WPF kontrolleri ve yerel dosya kilitleri kullanıldı. Bu sonuç sıfır hata garantisi veya şirket ağı kabulü değildir.

## 1. Sonuç ve kanıt

Son doğrulama: 50 bağımsız test dosyası geçti; 67 PowerShell dosyasında parse hatası yok. Sayılar test dosyasıdır; tekil assertion veya test edilen gerçek hedef sayısı değildir. İlk 34 dosyalı başlangıç turu da geçti; buna rağmen bağımsız inceleme ve yeni hata senaryoları aşağıdaki sorunları ortaya çıkardı.

Tam test çıktısı [KAPSAMLI_TEST_SONUCLARI.csv](KAPSAMLI_TEST_SONUCLARI.csv), güncel doğrulama/dağıtım hash kaydı [DOKUMAN_DOGRULAMA.json](DOKUMAN_DOGRULAMA.json) içindedir. Düzeltmelerden önce ilgili yeni testlerin hata verdiği, düzeltmelerden sonra geçtiği doğrulandı.

## 2. Bulunan ve düzeltilen sorunlar

| Alan | Önceki hata | Düzeltme ve doğrulama |
| --- | --- | --- |
| Registry geri alma | Değişiklik önce yapılıyor, manifest sonra yazılıyordu. Disk hatasında eski değer kaybolabilirdi. | Eski değer atomik manifest olarak değişiklikten önce saklanır. Yazılamazsa uzak Set/Delete çağrılmaz. Edit ve Delete test edildi. |
| Registry okuma hatası | Dönüş kodu 1, değer yokmuş gibi kabul edilerek yazma/silme yapılabiliyordu. | Yalnızca 2 kesin bulunamadı sayılır; 1 ve erişim reddi 5 için değişiklik engellenir, okuma Failed raporlanır. Üç akış da test edildi. |
| Servis geri alma | Servis durum/başlangıç türü manifesti operasyon sonuna kalıyordu. | Eski durum önce atomik kaydedilir; disk hatasında servis değiştirilmez. Stop ve Startup test edildi. |
| Paket JSON türleri | Dizi/nesne olarak gelen ad/açıklama gibi alanlar doğrulamadan geçip aramada hata oluşturabiliyordu. | Metin alanlarında JSON string tipi zorunlu. Hatalı import hedef kataloğa yazmadan reddedilir. |
| Kategori filtresi | Son paket başka kategoriye taşınınca ekranda Tüm kategoriler seçiliyken liste boş kalabiliyordu. | Filtre yenilenen seçime göre hesaplanır; gerçek WPF düzenle/kaydet akışı test edildi. |
| Profil kimliği | Main silinince başka bir kayıt sessizce Main yapılıyor ve kayıtlı hesap yerine mevcut token ile çalışabiliyordu. | Diğer kayıtların credential/Main anlamı korunur; otomatik terfi kaldırıldı. |
| Rapor zamanı | ISO string CompletedAt, işlem bitişi yerine rapor yazılma zamanı olarak kaydediliyordu. | Serileştirilmiş bitiş zamanı korunur; geçmiş gün/saat testi eklendi. |
| Kesilen dağıtım | Beklenmedik Runner çıkışı hedefleri hâlâ çalışıyor/bekliyor gösterebiliyordu. | Bilinen sonuçlar korunur; doğrulanmamış hedef belirsiz, sonucu hiç oluşmamış hedef hata olur. Kısmi rapor kurtarılır. |
| Son ilerleme özeti | Hedef durumları güncellenmeden eski başarı/hata sayısı yazılıyordu. | Özet hesaplandıktan sonra ilerleme metnine eklenir; son tick testi eklendi. |
| Eski checkpoint | Aynı bilgisayar için başka çalışmanın başarısı yeni sonuca taşınabiliyordu. | Çalışma ve paket kimliğiyle kapsam daraltılır. D4 hedef kimliğinin 10.000 ve üzerindeki indeksleri de desteklenir. |
| ProductID eşleşmesi | İlk kayıt bulununca tarama kesiliyor, diğer eşleşmeler ve tam anahtar seçimi görünmüyordu. | Bütün eşleşmeler toplanır; birden fazla kayıt belirsiz sayılır, tam anahtar filtresi tüm adayları görür. |

## 3. Test kapsamı

Registry dönüş kodları [Microsoft sistem hata kodları](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-) ve [StdRegProv GetStringValue](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/regprov/getstringvalue-method-in-class-stdregprov) belgeleriyle kontrol edildi.

| Grup | Sınanan davranış |
| --- | --- |
| Paket kataloğu | Şema, Unicode, revizyon, silme, kopyalama, import/export, özel alanların dışlanması ve bozuk veri. |
| Eşzamanlı kayıt | Aynı revizyona sekiz gerçek PowerShell yazıcısı: bir kayıt başarılı, yedi çakışma; JSON/revizyon sağlam ve geçici dosya sızıntısı yok. |
| Dağıtım | Install/Uninstall/Downgrade, bağımsız kimlikler, tam/alt sınır sürüm politikaları, kaynak erişimi ve sahte worker çıkış kodları. |
| Kesinti | İptal, force stop, checkpoint, kısmi rapor, eski çalışma izolasyonu ve beklenmedik worker başlangıç hataları. |
| Paralellik | Tek hedefli worker süreçleri, sıralı geri dönüş, hata izolasyonu ve canlı hedef snapshot'ları. |
| WPF | Başlangıç, paket kaydı/aktarımı, ad/kategori kalıcılığı, kısa ekran, ortak hedef tablosu ve sütun okunabilirliği. |
| Rapor | Hedef başına tek özet, adım ayrıntıları, exit/log alanları, HTML escaping, karma başarısız hedefler, günlük kırılımlar ve zamanlar. |
| Dosya/registry/servis/görev | Onaylar, kapsam ve geri alma kayıtları; hash/yedek kontrolleri, korunan hedefler ve hatalı yöntem dönüşleri. |
| Log toplama/temizleme | Başarı/timeout/hata kapıları, kullanıcı adı sınırları, değişen/kilitli/korunan dosyalar ve sayısal sınır. |
| Başlatıcı/hesap | Windows PowerShell 5.1, gizli süreçler, Main/credential sınırı, preflight yolları ve parola aktarım biçimi. |

## 4. Şirket ortamında kalan doğrulama

Yerel fixture testleri şu koşulları kanıtlamaz: domain hesabının gerçek hedef yetkisi, SMB/DCOM erişimi, EDR/PsExec davranışı, SYSTEM hesabının UNC ve script bağımlılıklarını okuması, gerçek yükleyici exit code/registry kaydı ve reboot sonrası uygulama durumu. Şirket testinde önce tek hedef ve paralellik 1 ile [pilot tablosu](PAKET_YONETIMI_PILOT_KONTROLU.md) doldurulmalıdır.

Fotoğraftaki 50010 kodunun kaynağı henüz belirlenmedi. İlgili Results.csv, RemoteOps.log ve paket/PsExec çıktısı olmadan neden atanmamıştır. Kod başarıya çevrilmedi ve yeni düzeltmeler bu hatanın gerçek paket nedenini çözmüş sayılmaz.

## 5. Dağıtım ve sınırlar

Bu turda hem RemoteOps.App hem Modules altında kaynak değişti. Şirket kopyasını güncellerken iki klasör birlikte taşınmalıdır. Kaydedilmiş profiller/paketler APPDATA altında, çalışma verileri C:\Temp\YD_RemoteOps.App altındadır; bunlar dağıtım klasöründen ayrıdır.

FullLanguage Windows PowerShell 5.1 çalışma varsayımıdır. Kilitler ayrı operatör bilgisayarları arasında merkezi koordinasyon sağlamaz. Otomatik reboot, retry, eski paketi geri kurma veya tam GUI çökmesi sonrası otomatik resume yoktur. Geri alma dosyaları ve yedekler birlikte tutulur; DeleteBackups saklama süresi uzun vadeli arşiv değildir.

## 6. İnceleme ve dokümanlar

İki bağımsız inceleme paket/arayüz ve dağıtım/kurtarma akışlarını kontrol etti. Bulgular yerel testlerle yeniden üretildi; düzeltmeler ve incelemede bulunan sınır durumları yeniden doğrulandı. Kılavuz ve teknik el kitabı bu sonuçlarla eşitlendi. Güncel ekran görüntüleri örnek verilerdir.


## 7. Çalıştırma görünümü güncellemesi

Son çalıştırma varsayılan görünümü, önceki çalıştırmaya dönüş, arka plan güncellemelerinde seçim korunması, aynı bilgisayarın ayrı gruplarda gösterimi ve seçili rapor izolasyonu eklendi. RemoteOps.RunSelection.Tests.ps1 bu davranışları sınar; tam pencere başlangıç testi gerçek ComboBox SelectionChanged olayını ve gruplamayı doğrular. Seçim olayında SelectedItem kullanılır. Rapor klasörü bağlantısı yazılmadan önce Runner yol kapsamı doğrulanır.


## 8. Erişilemeyen hedefler ve log kısayolları

Kayıtlı paketlerde gerçek WMI/DCOM ön kontrolü eklendi; erişilemeyen ve yetki reddi olan hedeflerde paket çalıştırılmaması, diğer hedeflerin devam etmesi Runner entegrasyon testinde doğrulandı. Genel kimlik mesajı yerine orijinal tespit hatası da korunur. TargetAccess ve DetectionErrors testleri üç paket eylemini kapsar. LogNavigation testi aynı istemcinin iki farklı çalıştırmadaki dosyalarını ayırır ve yanlış/eksik klasörleri kapatır. Gerçek WPF başlangıç testi üst ve istemci log düğmelerinin doğru yolu açmasını sınar. Gerçek şirket ağı erişimi ve log izinleri yine pilotta doğrulanmalıdır.


## 9. Ayrı eski sürüm paketi

Normal Install ve eski sürüm Downgrade tanımları bağımsız hale getirildi. Normal 5.0/eski 2.0 kaynak/kimlik/sürüm ayrımı motor ve gerçek izole Runner entegrasyonunda doğrulandı. UI üçüncü kart, kaydetme, kopyalama, doğru kaynak/sürüm içeren onay özeti test edildi. /1 anlam koruyan geçiş, okurken dosyaya dokunmama, kaydederken /2 revizyonu ve /1 import testleri eklendi. /2 schema ve export sürümü eski okuyucuda sessiz yanlış eylemi önler. Şirket kopyasında RemoteOps.App içindeki dosyalar birlikte güncellenmelidir.


## 10. v10 örnekler, çekilen dosyalar ve canlı test

Klasör v10 olarak yeniden adlandırıldı. Dosya/registry/task/service/process girişlerine açıklayıcı örnekler ve çalışma/istemciye bağlı çekilen dosya kısayolları eklendi. Gerçek WPF buton yönlendirmeleri ve örneklerin boş girişleri doldurmaması test edildi. Türkçe kültür ASCII I doğrulaması ile DCOM görev silme Confirm uyumsuzluğu canlı turda bulundu, regresyon testleriyle düzeltildi.

Mevcut bilgisayarda yönetici token ile 18/18 gerçek canlı senaryo geçti: SMB/DCOM erişimi; dosya pull/push/compare/yedekle-sil-restore/browse/move-replace rollback; registry read/edit/delete/rollback; servis list/start/restart/stop/startup rollback; görev list/disable/enable/run/delete/XML rollback; sahip olunan süreç query/kill. Altı cleanup kontrolü true, CleanupErrors boş. [Canlı test raporu](CANLI_TEST_RAPORU.md), [ham sonuç](live-test/LOCAL_LIVE_TEST.json), [CSV](live-test/LOCAL_LIVE_TEST.csv) bulunur. Bu yerel doğrulama şirket domain kabulünden ayrıdır; gerçek paket kurulumu yapılmadı.


## 11. v11 ortak erişim ve sonuç sınıflandırması

Bütün yerleşik operasyonlar aynı hedef ön kontrolünü kullanır. SMB ve WMI bağımlılıkları operasyonun gerçek ihtiyacına göre seçilir; kontrolsüz script WMI gerektirmez. Erişilemeyenler sarı/neutral grubundadır, gerçek hatalar kırmızı kalır. Ham Unreachable geçmişi korunur. Bağımsız incelemede atlanan paket metadata kaybı, eksik ağ hata kodları, SMB zaman sınırı ve geçersiz operasyonun erişilemedi diye sınıflandırılması yakalandı; düzeltmeler testlerle doğrulandı.

Yeni BatchAccess, OperationAccess, UnreachableClassification, BoundedProbe ve UncheckedScript testleri eklendi; gerçek WPF satır rengi de sınanır. v11'de mevcut bilgisayarda 26/26 salt okunur operasyon erişim kontrolü geçti; hedefte gerçek operasyon/mutasyon çağrılmadı. Ayrıntı live-test-v11/ACCESS_LIVE_TEST.json içindedir. v10'daki 18/18 mutasyon ve geri alma sonucu tarihsel kanıt olarak korunur.


## 12. İlk GitHub kaynak yayını

Uygulama ve modül kaynakları v11 ile bayt düzeyinde korunur. Repo için README, değişiklik notları ve regresyon başlatıcısı eklenmiştir. PsExec.exe üçüncü taraf indirmesi olarak ayrılmış; kişisel bilgisayar adları, kullanıcı yolları ve ham operasyon logları public test kanıtlarından çıkarılmıştır. Public JSON/CSV özetleri gerçek test sonuçlarını değiştirmez.
