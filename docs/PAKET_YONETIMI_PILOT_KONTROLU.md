# RemoteOps paket yönetimi pilot kontrolü

14 Ekim 2026 · YD_RemoteOps.App_v11. İlk pilot geri bildirimi alındı; gerçek OperationID/rapor bilgileri paylaşılmadığından kayıt alanları operatörün doldurması için boştur. [Kullanım kılavuzu](KULLANIM_KILAVUZU.md), [teknik el kitabı](TEKNIK_EL_KITABI.md) ve [yerel doğrulama raporu](INCELEME_RAPORU.md) test öncesi okunmalıdır. İlk senaryolar tek hedef ve paralellik 1 ile yapılır; log temizleme başlangıçta kapalı tutulabilir.

Pilot, şirketin belirlediği test bilgisayarlarında ve gerçek dağıtım paketleriyle yapılır. Yerel mock testleri, şirket ağındaki hesap ve SYSTEM erişimini doğrulamaz. Başlamadan test bilgisayarı ve paketlerin sorumlu ekip tarafından belirlenmesi gerekir.

| Bilgi | Değer |
| --- | --- |
| Test bilgisayarı | |
| Çalıştırma hesabı | |
| Uygulama ailesi | |
| Mevcut uygulama kimliği ve sürümü | |
| Hedef uygulama kimliği ve sürümü | |
| Kurulum UNC klasörü ve dosyası | |
| Kaldırma UNC klasörü ve dosyası | |
| Önceki sürüm için kurtarma paketi ve sorumlusu | |
| Pilot tarihi ve operatör | |

## Kabul senaryoları

| Kontrol | Beklenen sonuç | Gerçek sonuç ve OperationID |
| --- | --- | --- |
| Kaydet ve uygulamayı yeniden aç | Paket kaydı korunur; hedefte değişiklik olmaz | |
| Alternatif hesapla kaydı çalıştır | Runner operatörün APPDATA dosyasına ihtiyaç duymadan çalışır | |
| Seçili hesap ve hedef SYSTEM kaynak erişimi | İki hesap da gereken paket dosyalarını okuyabilir | |
| Uygulama yokken Kur | Paket kurulur; kimlik ve hedef/üst sürüm doğrulanır | |
| Uygulama varken Kaldır | Paket kaldırılır; kimliğe göre uygulama yokluğu doğrulanır | |
| Daha yeni sürümde Eski sürüme dön | Ön kontrol, kaldırma, yokluk, kurulum ve tam sürüm doğrulaması sırayla geçer | |
| Hedef sürüm zaten kurulu | Paket tetiklenmeden atlanır | |
| Kaldırma veya kurulum kaynağı erişilemez | Downgrade kaldırma yapmadan durur | |
| Yanlış kaldırma kimliği veya registry anahtarı | Paket çalıştırmadan hata verir | |
| Kaldırma paketi hata verir veya uygulama kalır | Kurulum başlatılmaz | |
| Kaldırma 3010 veya 1641 döndürür | Otomatik kurulum/reboot yapılmaz; gereksinim raporlanır | |
| Kaldırma sonrası kurulum başarısız | Uygulamanın kaldırıldığı açıkça raporlanır; otomatik retry yapılmaz | |
| Çok hedefte bir hata | Diğer hedeflerin sonuçları korunur; ledger hedef başına bir satırdır | |
| Durdur | Yeni hedef/adım başlatılmaz; aktif paket adımı biter; kısmi rapor oluşur | |
| Zorla durdur | Yerel süreçler kapanır; doğrulanmamış hedef belirsizdir; kısmi rapor oluşur | |
| Paket JSON paylaşımı | Kimlikler ve sürüm korunur; parola ve hedefler aktarılmaz | |
| 1366x768 ve yüzde 125 ekran | Ana eylemler ve kaydet düğmesi erişilebilir; içerik kaydırılabilir | |
| Aynı hedef/aile için ikinci yerel çalışma | Çakışan dağıtım kilitle engellenir; farklı operatör bilgisayarları ayrıca koordine edilir | |
| Scriptin çağırdığı MSI/EXE/config erişimi | Tam script probe'u dışında bağımlılıklar da hedef SYSTEM altında okunabilir | |
| Normal Kur sonrası daha yeni sürüm / downgrade sonrası farklı sürüm | Normal Kur AtLeast kabul eder; downgrade Exact ister | |
| Rapor ve snapshot | PackageDefinition.json, terminal sonuç ve hedef başına tek ledger kaydı doğru | |

Her senaryoda ilk sürüm, son sürüm, exit code, eylem adımı ve rapor klasörü ayrıca not edilir. Dosya geri alma testinde DeleteBackups alanının modül başlangıcında 7 günden eski yedekleri temizlediği dikkate alınır; kurtarma paketi bu alana bırakılmaz.

## Pilot sonrası karar

Başarısız veya belirsiz hedeflerde uygulama varlığı ve sürümü yeniden kontrol edilir. Timeout veya zorla durdurmada uzaktaki paket hâlâ çalışabileceğinden sonuç anlaşılmadan tekrar dağıtım yapılmaz. Uygulama kaldırılmış fakat hedef paket kurulamamışsa sorumlu ekip, önceden belirlenen kurtarma paketini değerlendirir.

Pilot tamamlandıktan sonra sonuçlar, OperationID ve rapor klasörüyle bu tabloya yazılır. Dağıtım paketine profil, parola, runtime log veya kullanıcı paket kataloğu eklenmez.

## 14 Ekim geri bildirim tekrar testleri

| Senaryo | Beklenen | Gerçek sonuç / OperationID |
| --- | --- | --- |
| Operasyon manuel paket formunu editöre aktar | Uygulama açık kalır; ad/kategori düzenlenir, kayıtta korunur | |
| Paket 50010 gibi bir hata kodu döndürür | Tek hedef özeti kod/log bilgisiyle görünür; özgün adımlar açılabilir | |
| İki farklı operasyonu birlikte izle | Her hedef doğru iş etiketi ve sonuçla görünür; satırlar birbirini ezmez | |


## Bağımsız eski sürüm tanımı

| Senaryo | Beklenen | Sonuç |
| --- | --- | --- |
| Normal kurulum 5.0, eski hedef 2.0, mevcut 3.0 | Downgrade yalnızca eski 2.0 kaynağını kullanır; normal Kur ayrı kalır | |
| Normal kurulum kapalı, kaldırma ve eski sürüm açık | Eski sürüme dön kullanılabilir; Kur pasiftir | |
| Eski sürüm dosyası/kimliği/sürümü eksik | Kaydetme/başlatma reddedilir | |
| /1 kayıt okuma ve /2 kaydetme | Okuma dosyayı değiştirmez; kaydetme revizyonu yükseltir; yollar operatörce doğrulanır | |
