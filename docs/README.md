# RemoteOps doküman dizini

[v28 yeni özellikler ve test kapsamı](V28_TEST_RAPORU.md) · [v28 sonuç ekranı](screenshots-v28/v28-adim-sonuclari.png)

16 Ekim 2026 · YD_RemoteOps.App_v28

Şirket pilotundan önce kullanım için kılavuzu, sistemin tamamını anlamak için teknik el kitabını okuyun. Markdown kaynaklar ve PDF'ler aynı güncel yapıyı anlatır. Görseller örnek verilerle gerçek WPF arayüzünden üretilmiştir.

| Doküman | İçerik | PDF |
| --- | --- | --- |
| [Kullanım kılavuzu](KULLANIM_KILAVUZU.md) | Dokuz sekme, profil, paket, downgrade, durdurma, sonuç okuma ve ekranlar. | [Kılavuz](../KULLANIM_KILAVUZU.pdf) |
| [Teknik el kitabı](TEKNIK_EL_KITABI.md) | Bütün dosyalar, süreç/hesaplar, uzak yöntemler, 26 operasyon, veri yolları, sınırlar ve bakım. | [El kitabı](RemoteOps_Teknik_El_Kitabi.pdf) |
| [Çalışma mantığı](CALISMA_MANTIGI.md) | Mimari ve paket akışının kısa açıklaması. | [Akış rehberi](RemoteOps_Calisma_Mantigi.pdf) |
| [İnceleme raporu](INCELEME_RAPORU.md) | Güncel yerel doğrulamalar, bilinen test referans sorunu ve pilot sınırı. | [İnceleme](RemoteOps_Inceleme_Raporu.pdf) |
| [Gelecek operasyon tasarımı](GELECEK_OPERASYON_OLUSTUR.md) | Henüz uygulanmamış genel reçete motoru; mevcut paket yönetiminden farkı. | [Tasarım](RemoteOps_Operasyon_Olustur_Tasarim.pdf) |
| [Pilot kontrolü](PAKET_YONETIMI_PILOT_KONTROLU.md) | Şirket testinde doldurulacak kabul senaryoları. | Markdown kayıt tablosu. |
| [Paket geliştirme planı](PAKET_YONETIMI_GELISTIRME_PLANI.md) | Uygulanmış paket tasarımının kararı ve kapsamı. | Markdown tasarım kaydı. |

## Dağıtım ve veri

Kökteki YD_RemoteOps.App.bat, PsExec.exe, Modules ve RemoteOps.App içindeki bütün dosyalar birlikte tutulur. tests ve docs çalışma bağımlılığı değildir, geliştirme ve operatör desteğidir. Eski MD_Script.ps1, CLM runner ve örnek Plugins bu dağıtımda yoktur. Windows PowerShell 5.1/FullLanguage ve WPF varsayılır; gerçek şirket ağı uyumluluğu pilotla doğrulanacaktır.

Runtime veri kökü C:\Temp\YD_RemoteOps.App; kişisel profiller/ayarlar/katalog %APPDATA%\MDRemoteOps altındadır. Dağıtım klasörü adını değiştirmek bu yolları değiştirmez. Paylaşımda kişisel profil/parola, şirket çıktıları ve yedekler pakete eklenmemelidir. Paket kaynakları UNC üzerinde ayrıca hazırlanır.

## Doküman bakımı

PDF üreticisi tools/build_documents.py, ekran üreticisi tools/capture_documentation.ps1'dir. Paket görselleri tests/RemoteOps.PackageLibraryUi.Tests.ps1 -PreviewDirectory docs/paket-ui-preview ile üretilir. Güncel yerel test kayıtları V18_TEST_RESULTS.csv içindedir; önceki doğrulama dosyaları tarihsel kanıttır. docs/superpowers altındaki plan/inceleme kayıtları tarihsel geliştirme kanıtıdır; içlerindeki önceki klasör/yedek yolları güncel runtime yolu değildir.

14 Ekim kapsamlı güvenilirlik denetimi: [bulgular ve doğrulamalar](INCELEME_RAPORU.md), [tam test çıktısı](KAPSAMLI_TEST_SONUCLARI.csv). Tarihsel v11 regresyon turu toplam 50 test dosyasını kapsar.


v10 güncellemesi: [yerel canlı test raporu](CANLI_TEST_RAPORU.md), 18/18 gerçek senaryo ve temizlik kanıtı. Bu kayıt v10 canlı testinin tarihsel kanıtıdır.


v11: ortak işlem öncesi erişim, sarı erişilemedi sonuçları ve sürümsüz script regresyonu. [Salt okunur yerel bağlantı kanıtı](live-test-v11/ACCESS_LIVE_TEST.json): 26/26; önceki v10 mutasyon testinden ayrıdır. Dağıtım sürümü [VERSION.json](../VERSION.json) içindedir; sonraki tamamlanan teslimler bir artırılarak yeni ZIP halinde hazırlanır. Drive yüklemesi yalnızca kullanıcı istediğinde yapılır.

## v12 teslimi

Restore file backup içindeki Backup number metin alanı tarih, bilgisayar ve dosya yolunu gösteren yedek listesiyle değiştirildi. Sabit klasör kimliği sayesinde liste sırası değişse de seçilen yedek korunur. Ayrıntılar kullanım kılavuzundaki v12 bölümünde, test kaydı BACKUP_SELECTION_VALIDATION.txt içindedir.

## v13 teslimi

Registry ve servis/task rollback için tarih/bilgisayar/değişiklik seçimi eklendi. Registry seçenekleri hangi anahtar/değerin kayıtlı hangi değerden hangi eski değere döneceğini gösterir. HKLM/HKEY_LOCAL_MACHINE, HKCU/HKEY_CURRENT_USER ve HKU/HKEY_USERS yolları tüm Registry operasyonlarında desteklenir. HKCU hedefteki tekil etkileşimli kullanıcının SID'sine çözülür ve rollback bu SID'yi korur. Güncel yerel test kaydı REGISTRY_ROLLBACK_VALIDATION_v13.txt içindedir.

## v14 teslimi

Registry operasyonları REG_SZ yanında REG_DWORD, REG_QWORD, REG_MULTI_SZ ve REG_EXPAND_SZ destekler. Düzenleme mevcut türü korur; yeni değer türü seçilebilir. Rollback eski tür ve veriyi geri yükler; seçim listesi türü gösterir. REG_EXPAND_SZ ham yedeği için uzak Remote Registry okuma erişimi gerekir. Güncel test kayıtları REGISTRY_TYPES_VALIDATION_v14.txt/CSV içindedir.

## v15 teslimi

Geçmiş ve Hata Teşhisi sekmeleri, geçmiş filtreleme, hedef/adım ayrıntıları, rapor/log kısayolları ve önizlemeli tanı ZIP'i eklendi. Kaynaklara RemoteOps.History.ps1, RemoteOps.Diagnostics.ps1 ve RemoteOps.HistoryUi.ps1 eklendi; RemoteOps.App ve Modules içindeki tüm dosyalar birlikte tutulmalıdır.

[Güncel testler](V15_TEST_RESULTS.csv), [doğrulama manifesti](V15_VALIDATION.json), [v15 inceleme özeti](V15_INCELEME.md). v11/v14 kayıtları tarihsel kanıttır. Yeni ekranlar gerçek WPF kontrollerinde örnek verilerle doğrulandı; şirket hedeflerinde canlı işlem yapılmadı. Drive yüklemesi yalnızca kullanıcı istediğinde yapılır.

## v16 teslimi

Hedef Grupları sekmesi ve paket/operasyon hedef alanlarında açık Ekle/Değiştir eylemleri eklendi. Genel operasyonlar çalıştırmadan önce önizleme gösterir; paketlerde mevcut özet paneli ortak modelle genişletildi. Önizleme salt yerel hazırlıktır; canlı ağ ön kontrolü değildir. v15 özellikleri korunur.

Güncel kayıtlar: [v16 inceleme](V18_INCELEME.md), [testler](V18_TEST_RESULTS.csv), [doğrulama](V18_VALIDATION.json). Önceki sürüm kayıtları tarihsel kanıttır. Drive yüklemesi yapılmaz.


## v17 teslimi

Birleşik Geri Alma Merkezi sekizinci sekmedir. [v17 inceleme ve doğrulama](V18_INCELEME.md), [test sonuçları](V18_TEST_RESULTS.csv), [dosya/parse kaydı](V18_VALIDATION.json). Güncel ekran üreticisi tools/capture_v17.ps1, ekranlar screenshots-v17 altındadır. Önceki sürüm kayıtları tarihsel kanıt olarak korunur.


## v18 teslimi

[İnceleme ve kapsam](V18_INCELEME.md) · [Testler](V18_TEST_RESULTS.csv) · [Doğrulama](V18_VALIDATION.json). Güncel görseller screenshots-v18, üretici tools/capture_v18.ps1 altındadır. Dokuzuncu sekme Operasyon Reçeteleri uygulandı; önceki sürüm belgeleri tarihsel kanıttır.


## v19 — Rapor okunabilirliği

Türkçe metinlerin Windows PowerShell 5.1 altında bozulmasına yol açan kaynak kodlaması düzeltildi. Yeni raporlarda sütunlar okunabilir genişlikte kalır; dar ekranda tablo yatay kaydırılır. Teknik kimlikler, hash ve revizyon alanları satırdaki **Ayrıntı → Teknik kimlikler** bölümündedir. Arama bu alanları da kapsar. CSV özgün alanlarını korur; çalıştırılmayan adımlar ekranda **Çalıştırılmadı** olarak görünür.

Düzeltme yeni üretilen raporlar içindir. Önceden bozulmuş HTML/CSV kayıtları otomatik değiştirilmez.

73/73 yerel test geçti; gerçek Edge ile normal ve yüzde 125 ölçek, ayrıntı, arama, sıralama ve yazdırma kontrol edildi. Bu teslimde canlı uzak hedef testi ve Drive yüklemesi yapılmadı.

![v19 okunabilir rapor](screenshots-v19/rapor-normal.png)

[Ayrıntı görünümü](screenshots-v19/rapor-ayrinti.png) · [Yüzde 125 görünümü](screenshots-v19/rapor-125.png) · [Doğrulama](V19_VALIDATION.json)


## v20 — Teşhis seçimi ve görev yedeği kodlaması

Hata Teşhisi çalışma listesinde operasyon adı, tarih/saat ve kayıtlıysa paket/reçete adı görünür. Örnek: **Paket dağıtımı · Örnek paket · 15.10.2026 13:58:32**. Teknik çalışma kimliği teşhis ayrıntısında korunur; seçim yine aynı kayıt nesnesine bağlıdır.

Görev silmeden önce alınan XML yedeğinde UTF-16 bildiriminin UTF-8 dosya baytlarıyla uyuşmaması Geri Alma Merkezi okumasını engelliyordu. Eski UTF-8 yedekler dosyaya yazılmadan okunur; gerçek BOM içeren UTF-16 yedekler de desteklenir. Yeni yedekler XML yazıcısıyla tutarlı UTF-8 olarak kaydedilir. DTD ve dış kaynak çözümleme yasakları, hedef kapsamı ve mevcut görevin üzerine yazmama kontrolleri korunur.

Bu hata daha önce geri alma yapılmış olmasına bağlı değildir. Önceden geri yüklenmiş görev hedefte mevcutsa tekrar geri alma işlemi mevcut görev üzerine yazmaz. Dosyanın okunabilmesi hedefte geri alma başarısı garantisi değildir.

Doğrulama yerel dosya örnekleri, sahte uzak sınırlar ve gerçek WPF çizimiyle yapılmıştır. Bu teslimde canlı uzak görev değiştirilmedi; Drive yüklemesi yapılmadı.

![v20 teşhis görünümü](screenshots-v20/hata-teshisi.png)

[Yüzde 125 görünümü](screenshots-v20/hata-teshisi-125.png) · [v20 doğrulaması](V20_VALIDATION.json)


## v21 — Anlaşılır teşhis ve geri alma durumları

Hata Teşhisi ekranında teknik ayrıntıların üstünde **Neden oldu?** ve **Ne yapmalıyım?** açıklamaları gösterilir. Bilinen sürüm atlama mesajı açıkça açıklanır; genel atlama veya bilinmeyen hata için kanıtsız bir neden atanmaz. Yetki/kaynak/doğrulama sınıfları kayıt işaretleridir; kesin kök neden iddiası değildir.

Geri Alma Merkezi yerel yedek durumu, eşleşen yerel geri alma geçmişi ve hedefin güncel durumunu ayrı gösterir. Eksik dosya veya okunamayan görev XML'i anlaşılır başlıkla belirtilir; özgün hata ayrıntıda kalır. Listeye bakmak hedefe bağlantı kurmaz. **Hedefin güncel durumu sorgulanmadı** ifadesi bu nedenle gösterilir.

v21 itibarıyla Geri Alma Merkezi üzerinden tamamlanan denemeler, çalışma raporu yanında **RecoveryReceipt.json** yerel sonuç kaydı üretir. Eşleştirme bilgisayar, kayıt kimliği, manifest özeti, yedek damgası, tür ve seçilmiş satır anahtarlarıyla yapılır. Kayıtlardaki başarı güncel hedef durumunun doğrulandığı anlamına gelmez. Eski çalışmalar ve diğer yollardan yapılan geri almalar için eşleşen kayıt bulunmayabilir; kayıt yokluğu hiç geri alınmadığını kanıtlamaz. Manifest veya yedek değişirse eski sonuç yeni kapsamın sonucu olarak gösterilmez.

**Son geri alma: başarılı bildirildi** yalnızca seçili kapsama ait yerel sonuçların başarı bildirdiğini söyler. Eksik/başarısız sonuçlarda tam başarı doğrulanmadığı belirtilir. Sonuç kaydı yazılamazsa uyarı kaydedilir; asıl uzak işlem sonucu değiştirilmez. Bu dosyalar yerel operatör kaydıdır, imzalı denetim kanıtı değildir.

![Anlaşılır hata teşhisi](screenshots-v21/hata-teshisi.png)

![Geri alma durumları](screenshots-v21/geri-alma.png)

[Eksik yedek görünümü](screenshots-v21/geri-alma-eksik.png) · [Yüzde 125 görünümü](screenshots-v21/geri-alma-125.png) · [Doğrulama](V21_VALIDATION.json)

Ekranlar örnek verilerle gerçek WPF çizimidir. Testler yerel örnekler ve sahte uzak sınırlar kullanır; bu teslimde canlı uzak hedef değiştirilmedi. Drive yüklemesi yapılmadı. Önceki dağıtım korunur.
