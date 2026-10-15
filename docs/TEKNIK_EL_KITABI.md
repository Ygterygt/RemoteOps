# RemoteOps teknik el kitabı

16 Ekim 2026 · YD_RemoteOps.App_v28

## v28 — Otomatik sonuç doğrulama ve adım sonuçları

Servis başlatma, durdurma, yeniden başlatma ve başlangıç türü değişikliği sonrasında hedef tekrar okunur. Registry düzenlemede gerçek tür ve değer yeniden okunur; silmede değerin bulunmadığı kontrol edilir. Dosya gönderiminde gönderim öncesi kaynak özeti alınır; sonrasında kaynak sabitliği, hedef dosyaların SHA256 içerikleri ve klasörlerin varlığı/türü karşılaştırılır. Bu kontroller hem reçete adımlarında hem ilgili tekil işlemlerde otomatik uygulanır.

Komut yanıtı ve sonuç doğrulaması ayrı kaydedilir. “Doğrulandı” beklenen durumun kontrol anında görüldüğünü; “Beklenen sonuç oluşmadı” komut kabul edildiği halde sonucun farklı olduğunu; “Doğrulanamadı” son durumun okunamadığını veya kaynak değişimi gibi bir nedenle kesinleştirilemediğini anlatır. Komut başarısızsa veya gönderimde öğe atlandıysa doğrulama yapılmaz. Servis durum geçişinde en fazla 30 saniyelik bekleme penceresi kullanılır; her uzak okuma ayrıca en fazla 10 saniyelik sağlayıcı sınırına tabidir. Kontrol anındaki durumun daha sonra değişmeyeceği garanti edilmez.

Reçetede başarısız ya da belirsiz doğrulama o hedefte sonraki adımları durdurur; sonraki bilgisayarın reçetesi bağımsız devam eder. Tamamlanmış işlemler otomatik geri alınmaz, komutlar otomatik yeniden gönderilmez. Örneğin servis durdurulduktan sonra dosya gönderimi doğrulanamazsa servis başlatma adımı çalıştırılmaz. Geçmişte önceki adımın doğrulanmış durmuş durumunu ve sonraki adımın çalıştırılmadığını görebilirsiniz; bu geçmiş kaydı güncel canlı durum sorgusu değildir.

Geçmiş ekranında çalışma ve hedef seçildiğinde adım adı, komut yanıtı ve doğrulama sonucu görünür. Bir adım seçildiğinde beklenen ve gözlenen durum, açıklama ve UTC kontrol zamanı alt bölümde gösterilir. Çoklu koşullar tek adımda özetlenir; özgün satırlar CSV ve raporlarda korunur. HTML raporunda ayrıca okunabilir adım sonuçları tablosu vardır. Eski geçmiş kayıtlarında otomatik doğrulama kanıtı yoksa “Bu kayıtta otomatik doğrulama yok” yazılır.

Mevcut Recipe/1, /2, /3 ve /4 reçeteleri değiştirilmez; otomatik adlar, özel adlar, koşul grupları ve çalışma sırası korunur. Paket dağıtımının ve yedekleyerek silmenin önceki sonuç kontrolleri korunur; yeni servis/registry/gönderim kontrolü bunların yerine geçmez. Bağlantı/junction içeren dosya kapsamları doğrulanmış sayılmaz. Hedefte gönderim kapsamı dışında kalan dosyalar silinmez veya karşılaştırılmaz. Kaynak içerik özeti alınamıyorsa gönderim başlatılmaz.

Runtime C:\Temp\YD_RemoteOps.App ve katalog/profil yolları %APPDATA%\MDRemoteOps olarak kalır. Canlı hedeflere işlem yapılmadan yerel testler ve sınırlandırılmış SIM hedef modeliyle doğrulanmıştır; gerçek ağ, Windows sağlayıcısı, domain, SMB/PsExec ve EDR doğrulanmış değildir.

![v28 adım sonuçları — yerel örnek veri](screenshots-v28/v28-adim-sonuclari.png)

[Ayrıntılı v28 kapsamı ve test raporu](V28_TEST_RAPORU.md)

## Önceki teslimlerin tarihli referansları

Aşağıdaki v27 ve önceki bölümler tarihli arşiv açıklamalarıdır; v28 değişiklikleri yukarıda açıklanmıştır.

15 Ekim 2026 · YD_RemoteOps.App_v27

## v27 - v26 kodu için hafif operasyon kabul testi

Bu teslim uygulama davranışını değiştirmez. RemoteOps.App ve Modules içindeki 36 üretim dosyası v26 ile birebir aynıdır. v26 kaynak ve ZIP korunmuştur. Yeni teslim hafif test araçları, kayıtlar ve kabul raporunu ekler.

Gerçek WPF reçete oluşturma, otomatik ad, adım içi koşul, kaydetme/yeniden açma, önizleme ve RECETE onayı; gerçek koordinatör ve çocuk süreçleriyle sınandı. Uzak erişim sınırında yerel, durumu değişen servis/registry modeli kullanıldı. 17/17 operasyon senaryosu, 12/12 yerel regresyon dosyası ve 5/5 sınır negatif kontrolü geçti. Bağımsız inceleme 16 çalışma kaydını doğruladı. Çalışma yaklaşık 149 saniye sürdü; gözlenen toplam çalışma belleği yaklaşık 700 MiB idi. Sanal makine kullanılmadı.

Yanıltıcı Success raporu hedef durumuyla ayrıca karşılaştırıldı ve reddedildi. Koşul atlama/durdurma, All/Any, okuma/işlem hatası, iptal, hedef bağımsızlığı ve eski ortak koşul davranışı doğrulandı. Gerçek ağ/Windows sağlayıcısı, domain hesabı, SMB/PsExec ve EDR testi yapılmadı. Durdur onay kutusu yerine aynı gerçek iptal isteği mekanizması çağrıldı.

[Ayrıntılı kabul raporu](V27_HAFIF_TEST_RAPORU.html) · [Kod eşitliği](V26_CODE_IDENTITY.json)

Tekrar çalıştırmak için kökte HAFIF_TEST_CALISTIR.bat dosyasını açın. Çıktılar yeni tarihli klasöre yazılır. Kişisel veri yolları testte geçici dizine yönlendirilir; gerçek uygulamanın C:\Temp\YD_RemoteOps.App ve AppData yolları değişmez.

## v26 arayüzü ve önceki teslimlerin referansı

Aşağıdaki ekran görüntüleri ve v26 açıklamaları aynı kalan uygulama arayüzünün referansıdır. v27 yalnızca test teslimidir.


15 Ekim 2026 · YD_RemoteOps.App_v26

## v26 - Adımın içinde koşul ve otomatik adlandırma

Reçete ekranı adım listesine odaklanır. İşlem alanlarını doldurmak için Adım ekle veya seçili adımı düzenleme komutunu kullanın. Düzenleme ayrı pencerede açılır; işlem bilgileri ve çalışma koşulu ayrı bölümlerde tutulur. Ana sayfada aşağı kaydırarak alan aramak gerekmez. Uzun listeler kendi alanında kaydırılabilir.

Adım adına ayrıca metin yazmak gerekmez. İşlem ve ilgili servis, dosya veya registry bilgileri adı oluşturur. Örneğin Servisi başlat · Spooler. İsterseniz adı özelleştirebilirsiniz; eski reçetelerde verdiğiniz özel adlar korunur.

İlgili adımın çalışma koşulunda servis veya registry kontrolü tanımlayın. Registry değerinde tür seçilmez: 1 veya 16.0.444 gibi beklenen değeri girin. Gerçek hedef türüne göre karşılaştırma yapılır. Servis koşulunda yalnızca servisle ilgili alanlar görünür. Birden fazla kontrol için Tümü / Herhangi biri davranışı korunur. Koşul sağlanmazsa adımı atlama veya hedefin reçetesini durdurma seçilebilir.

Otomatik adlandırma tercihi yeni Recipe/4 biçiminde saklanır; yeniden açıldığında da güncellenir. Eski reçeteler ve özel adlar korunur. Yeni biçimdeki reçeteleri açmak için v26 gerekir.

Mevcut ortak koşulların bağlı adımları ve tek kez değerlendirilme davranışı korunur. Eski ortak koşul değiştirilirse aynı koşula bağlı bütün adımları etkiler; düzenleyici bu kapsamı belirtir. Yeni koşullar ilgili işlemle birlikte yönetilir. Uyumsuz sıra değişiklikleri engellenir. Düzenlemeden vazgeçmek kayıtlı reçeteyi veya taslağı değiştirmez.

Hedefler ayrı bölümde yönetilir; ortak hedef araçları korunur. Reçeteyi kaydetmek hedefte işlem başlatmaz. Kaydedilmiş reçetenin önizlemesi ve RECETE çalıştırma onayı devam eder. Gerçek uzak hedef testi bu teslimde yapılmamıştır.

![v26 reçete ekranı](screenshots-v26/recete-ana.png)

![Adımın çalışma koşulu](screenshots-v26/adim-kosulu.png)

## Önceki sürümlerin tarihsel açıklamaları

Aşağıdaki v25 ve daha eski bölümler kendi teslimlerini anlatır. Güncel v26 kullanımında üstteki adım düzenleme akışı geçerlidir.


15 Ekim 2026 · YD_RemoteOps.App_v25

## v25 — Kolay koşul oluşturma ve otomatik değer karşılaştırması

Koşullar artık ayrı bir Koşul ekle düğmesi yerine Adım ekle akışındadır. Yeni adımın Adımda ne yapılsın? listesinden Koşul: Registry değerini kontrol et, Koşul: Registry anahtarını kontrol et veya Koşul: Servisi kontrol et seçilir. Servisi başlat/durdur/yeniden başlat normal bir işlemdir; servis koşulu salt okunur kontroldür.

Registry değeri için yalnızca yolu, değer adını, Eşit/Eşit değil seçimini ve karşılaştırılacak değeri girin. Örneğin Version için 16.0.444 veya Mode için 1 yazın. Registry türü seçilmez: uygulama hedefte kayıtlı gerçek türü okur ve girdiğinizi o türe göre karşılaştırır. Metin değeri metin olarak, sayı değeri sayı olarak ele alınır. Olası türler sırayla denenmez. Sürüm metni sayıya çevrilmez. Sayı türüne uymayan beklenen metin eşit değildir; hedef okunamadıysa bu bir karşılaştırma sonucu sayılmaz ve o bilgisayardaki reçete durur.

Registry anahtarı seçildiğinde yalnızca yol ve var/yok kontrolü görünür. Registry değeri için Var/Yok seçildiğinde beklenen değer alanı da kapanır. Değer adı boş bırakılırsa varsayılan registry değeri kullanılır. Eksik değer Eşit değil koşulunu sağlamaz; eksikliği denetlemek için Yok seçilir. Metin karşılaştırması büyük/küçük harfe duyarlıdır.

Servis seçildiğinde registry yolu, registry türü ve serbest değer alanları görünmez. Servis adı ve kontrol amacı seçilir: Var/Yok, Servis durumu veya Başlangıç türü. Durum ve başlangıç Türkçe açılır listeden seçilir: Çalışıyor/Durduruldu ve Otomatik/El ile/Devre dışı gibi. Teknik sistem değerlerini yazmak gerekmez.

Tek kontrolde gereksiz Tümü/Herhangi biri seçimi gizlidir. Ek kontrol eklendiğinde bu seçenek görünür. Koşul sağlanmazsa bağlı adımları atlama veya o bilgisayarın reçetesini durdurma seçimi alanların altındadır. İlgili normal adımın Adımın koşulu alanından önceki koşula bağlanması, kapsam korumaları ve mevcut çalıştırma onayları devam eder. Önizleme koşulları cümleyle anlatır; hedefi sorgulamaz.

![Kolay registry koşulu](screenshots-v25/registry-deger-alani.png)

![Servis koşulunda yalnızca ilgili alanlar](screenshots-v25/servis-durum-alani.png)

Mevcut koşulsuz ve v24 koşullu reçeteler açılır. Eski karşılaştırma değiştirilmeden kaydedilirse kayıtlı tür kısıtı korunur. Eski koşulda beklenen değer veya karşılaştırma değiştirilirse yeni otomatik karşılaştırma kullanılır. Yeni otomatik koşullar v25 gerektirir; eski uygulamalar bu yeni reçete biçimini açamaz. Önceki dağıtım ve kişisel veri yolları korunur.

Çok satırlı registry değerinde her öğeyi ayrı satıra yazın; JSON bilmek gerekmez. Satır sırası, boşluklar ve boş satırlar önemlidir. Boş metin tek boş öğedir, sıfır öğeli dizi değildir. CRLF/LF satırları böler; tek CR harfi verinin parçası kalır. Önceden kayıtlı açık tür karşılaştırmaları değiştirilmedikçe eski kuralları kullanır. Desteklenen hedef türleri mevcut beş registry türüdür; desteklenmeyen veya bozuk hedef verisi hata olarak raporlanır.

Bu teslimde gerçek uzak hedef değiştirilmedi. Ekranlar yalıtılmış örnek verilerle gerçek WPF çizimidir. Aşağıdaki eski sürümlerin tür seçtiren veya ayrı Koşul ekle düğmeli açıklamaları tarihsel bilgidir; v25 arayüzünü anlatmaz.


15 Ekim 2026 · YD_RemoteOps.App_v25

## v24 — Registry ve servis koşullu reçeteler

Mevcut koşulsuz reçeteler aynı sırayla ve aynı onaylarla çalışır. Koşul eklenen reçeteler yeni şemayla kaydedilir; v23 ve daha eski uygulamalar bu yeni reçeteleri açamaz. Mevcut kişisel reçeteler otomatik dönüştürülmez.

Operasyon Reçeteleri ekranında Koşul ekle düğmesini kullanın. Koşula ad verin, Tümü sağlansın veya Herhangi biri sağlansın seçin. Denetim ekle ile bir grupta 1–10 kontrol tanımlayın. Registry anahtarı/değeri için Var/Yok, registry değeri için Eşit/Eşit değil; servis için Var/Yok, Servis durumu veya Başlangıç türü seçilebilir. Servis adını tam yazın. Durum için Running/Stopped gibi sistem değerleri, başlangıç türü için Automatic/Manual/Disabled kullanılır.

Registry karşılaştırmaları türü dikkate alır. REG_SZ, REG_EXPAND_SZ, REG_DWORD, REG_QWORD ve REG_MULTI_SZ desteklenir. Sayılar ondalık veya 0x biçiminde; çoklu metin JSON dizisi olarak girilir. Metinler büyük/küçük harfe duyarlı karşılaştırılır. Değerin bulunmaması Eşit değil koşulunu sağlamaz; bunun için ayrı Yok kontrolünü seçin. Anahtar kontrolünde değer adı ve beklenen tür/değer boş kalır. Servis kontrolünde registry yolu ve beklenen registry türü boş kalır. HKCU mevcut registry modülleriyle aynı tek etkileşimli kullanıcı SID çözümlemesini kullanır; belirsiz kullanıcı hatadır.

Koşuldan sonra normal Adım ekle ile işlemleri oluşturun. İlgili işlemde Adımın koşulu listesinden önceki koşulu seçin. Bağlı adımlar koşulun hemen ardından kesintisiz sıralanmalıdır; girintili görünür. Koşulsuz seçilen adım koşul bloğunu bitirir. Sonraki yeni koşul yeni bir blok başlatır. İç içe koşul ve ileri adıma başvuru yoktur. Bağlı adımları olan koşul doğrudan silinmez; önce bağlantıları düzenleyin. Geçersiz yeniden sıralama geri çevrilir. Reçete kopyalandığında koşul bağlantıları yeni kimliklerle korunur.

Yanlış sonuçta Bağlı adımları atla seçilirse yalnızca o koşula bağlı işlemler atlanır; sonraki koşulsuz adımlar devam eder. Bu hedefin reçetesini durdur seçilirse o bilgisayarda kalan işlemler başlamaz; sonraki bilgisayara geçilir. Erişim reddi, hatalı/eksik sağlayıcı sonucu ve okunamayan durum koşulun yanlış olması değildir: o hedef durur. Herhangi biri seçili ve bir kontrol doğru olsa bile başka kontrolde hata varsa işlemler başlamaz.

Koşullar her hedefte kendi adımına gelindiğinde salt okunur sorgularla değerlendirilir. Önizleme koşulları sorgulamaz; tanımları, bağlı adımları ve hesabı gösterir. Kaydedip önizlemeyi açın; mevcut RECETE onayı geçerlidir. Çalışma raporu her kontrolde beklenen/okunan değer ve eşleşmeyi, koşul nedeniyle atlanan işlemleri ve hataları saklar. Alt süreç sonuçları onaylı kontrol tanımına bağlanır; eksik veya tutarsız kanıt bağlı değişikliği başlatamaz.

![Koşul grubu](screenshots-v24/recete-kosullari.png)

![Koşula bağlı işlem](screenshots-v24/kosula-bagli-adim.png)

![Koşullu reçete önizlemesi](screenshots-v24/kosul-onizlemesi.png)

Örnek: Mode değeri mevcut ve Enabled değilse VE OrnekServis durmuşsa ayarı güncelle, servisi başlat. Mode yoksa gruptaki Eşit değil yanlış olur; eksik değeri de kapsamak isterseniz Yok için ayrı bir koşul grubu tasarlayın.

Sınırlar: toplam 20 adım sınırına koşul adımları da dahildir; grup başına 10 denetim. Koşul ile bağlı işlem arasında hedef durumu değişebilir; atomik işlem veya otomatik geri alma değildir. REG_EXPAND_SZ kayıpsız okumada mevcut Remote Registry yardımcısının erişim gereksinimleri geçerlidir. Bu teslim yerel sahte sınır ve WPF testleriyle doğrulanır; canlı şirket hedefi değiştirilmedi. Aşağıdaki eski sürüm açıklamaları tarihsel bilgidir; geçmişte koşul olmadığına ilişkin ifadeler v24 kapsamını anlatmaz.


15 Ekim 2026 · YD_RemoteOps.App_v25

## v23 — Ortak hedefler, sonuç filtreleri ve geçişler

Tek operatör için ikinci aşama. Paketlerim, Operasyon ve Operasyon Reçeteleri ekranlarında aynı hedef araçları bulunur. Seçili tekil hedef ve tekrar sayısı giriş sırasında güncellenir. Tekrarları temizle ilk yazılan adı koruyarak listeyi düzenler; geçersiz ad varsa girdi değişmez. Hedefleri düzenle penceresinde bilgisayar arayın, bir veya birden fazla hedefi seçip çıkarın ve Listeyi uygula ile kaydedin. Arama yalnızca görünümü süzer; aramada görünmeyen hedefler korunur. Vazgeç değişiklikleri uygulamaz. Açık pencere sırasında asıl hedef alanı değişirse eski liste uygulanmaz.

Hedefler üç ekran arasında otomatik eşitlenmez ve diske yeni bir ortak hedef listesi yazılmaz. Hedef gruplarına git kaydedilmiş kişisel listelerin ekranını açar; grubu hedef alanına aktarmak için dönüp Ekle/Değiştir seçilir. Her çalıştırmada mevcut önizleme ve onaylar geçerlidir.

Devam eden işler ve sonuçlar panelinde bilgisayar adı ve özgün sonuç kodu birlikte filtrelenebilir. Görünen / toplam hedef sayısı gösterilir; Filtreleri temizle bütün satırları geri getirir. Kaynak sonuç ve raporlar değişmez. İlerleme yenilenirken seçim çalışma ve bilgisayar kimliğiyle korunur; gizlenen satırın eski eylemleri açık kalmaz. Geçmiş ekranında hedef tablosu için ayrıca bilgisayar/sonuç filtresi vardır. Çalışma filtresi ile hedef filtresi ayrı kapsamları süzer.

Seçili sonucu teşhis et, ilgili çalışmanın rapor kökü ve hedefi eşleşiyorsa doğru teşhisi açar. Rapor henüz oluşmadıysa açıklama gösterilir. İzleme, Geçmiş ve Hata Teşhisi ekranlarından seçili bilgisayarın yedeklerine geçilebilir. Bu geçiş Geri Alma Merkezi filtrelerini ilgili bilgisayara ayarlar, önceki tür/tarih filtrelerini temizler ve bir geri alma kaydını otomatik seçmez. Hedefe bağlanmaz; geri alma başlatmaz.

![Ortak hedef seçimi](screenshots-v23/ortak-hedefler.png)

![Hedef listesini düzenleme](screenshots-v23/hedef-duzenle.png)

![Sonuç filtreleri](screenshots-v23/sonuc-filtreleri.png)

Bu teslimde uzak motor, çalışma hesapları, C:\Temp\YD_RemoteOps.App ve AppData yolları korunur. Gerçek uzak hedef testi yapılmadı. Ekranlar örnek verilerle gerçek WPF çizimidir. Aşağıdaki eski sürüm bölümleri ve ekranlar tarihsel bilgi olarak korunur.


15 Ekim 2026 · YD_RemoteOps.App_v25

## v22 — Tek operatör için yeni ekran düzeni

Uygulama tek operatör tarafından kullanılır. Farklı çalışma profilleri aynı operatörün uzak hedeflerde kullandığı hesaplardır. Ekip kataloğu, çok kullanıcılı onay veya operatörler arası merkezi kilit bu teslimin kapsamı değildir.

Üst sekmeler yerini üç gruplu sol menüye bırakır: Çalıştır (Paketlerim, Operasyon, Operasyon Reçeteleri), Hazırla (Paket Oluştur, Hedef Grupları), İncele ve Kurtar (Rapor, Geçmiş, Hata Teşhisi, Geri Alma Merkezi). Dokuz mevcut ekran ve Yeni paket / Düzenle gibi geçişler korunur. Dar pencerede menü kaydırılabilir. Uygulama başlığında kökteki VERSION.json sürümü görünür.

Teşhiste sonuç nedeni ve sonraki adım ayrı kartlardır. Özgün kayıtlar Teknik ayrıntılar ve özgün kayıtlar bölümünde açılır. Geri almada yerel yedek, son yerel sonuç ve hedefin güncel durumu ayrı kartlardır. Güncel durum otomatik sorgulanmaz; geçmişteki başarı hedefte şu an doğrulama yapıldığı anlamına gelmez. Kapsam ve teknik ayrıntılar açılır bölümde kalır. Filtrelerde kalıcı alan etiketleri vardır; liste ve ayrıntı genişlikleri ayarlanabilir.

Çalıştırma hesabı ve paralellik üstte, devam eden işler ile teknik etkinlik altta kalır. Yürütme motoru, onaylar, uzak işlem davranışları, C:\Temp\YD_RemoteOps.App ve AppData katalog/profil yolları değiştirilmedi. Bu teslim için uzak hedeflerde canlı test yapılmaz; ekranlar yalıtılmış örnek verilerle çizilir. Aşağıdaki önceki sürüm bölümleri tarihsel bilgi ve özellik açıklamasıdır; eski üst sekmeli görseller v22 gezinmesini göstermez.

![v22 teşhis ekranı](screenshots-v22/hata-teshisi.png)

![v22 geri alma ekranı](screenshots-v22/geri-alma.png)


15 Ekim 2026 · YD_RemoteOps.App_v25 · Mevcut kaynak kodun çalışma sözleşmesi

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
| Modules/RegistryOperations.ps1 | HKLM/HKCU/HKU tür bilgili değerleri okuma/değiştirme/silme ve geri alma kaydı. |
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
| Registry işlemleri | CIM StdRegProv | HKLM/HKCU/HKU altında REG_SZ, REG_DWORD, REG_QWORD, REG_MULTI_SZ ve REG_EXPAND_SZ değerleri. |
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
| RegistryRead | HKLM/HKCU/HKU RegistryPath / ValueName. | Salt okunur. |
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

Registry işlemleri HKLM/HKCU/HKU köklerinde REG_SZ, REG_DWORD, REG_QWORD, REG_MULTI_SZ ve REG_EXPAND_SZ türlerini destekler. HKCR ve HKCC kökleri de ayrıştırılır. Eski değer veya değerin önceden bulunmadığı bilgisi değişiklikten önce kaydedilir. Servis yöntemlerinin dönüş kodu kontrol edilir; yalnızca komut çağrıldı diye başarı yazılmaz.

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

## v12: Yedek seçiminin veri sözleşmesi

RemoteOps.Backups.ps1, DataRoot/DeleteBackups altındaki okunabilir manifest.csv kayıtlarını tarih sırasıyla listeler. Görünen metin LastWriteTime, manifest ComputerName ve OriginalPath alanlarını içerir. GUI BackupPath değerinde sıra numarası yerine sabit yedek klasör adını gönderir. Runner bu adı doğrular; restore menüsü aynı adı tam eşleşmeyle çözer. Eski sayısal istekler ve konsol seçimi uyumluluk için korunur. GUI boş seçimleri reddeder. Yenileme mevcut Refresh modules düğmesiyle yapılır.

## v13: Hive ve rollback veri sözleşmesi

Modules/RegistryPaths.ps1 tüm registry işlemlerinin ortak kök ayrıştırıcısıdır. Kısa ve uzun hive adları, isteğe bağlı iki nokta ve Registry:: sağlayıcı öneki desteklenir. HKLM varsayılandır; geçersiz kök, boş alt anahtar ve nokta segmentleri reddedilir. HKCU için Win32_LogonSession etkileşimli oturum türleri 2, 10 ve 11; Win32_LoggedOnUser ilişkisi ve Win32_Account SID alanı kullanılır. Tekil kullanıcı SID'si HKEY_USERS altında doğrulanır. Birden çok oturum aynı kullanıcıya aitse tek SID olarak değerlendirilir; birden çok SID belirsizdir.

Registry manifestleri RegistryHive ve tam RegistryPath alanlarını saklar; HKCU girdisi çözülmüş HKU SID yoluyla kaydedilir. Read/edit/delete StdRegProv hDefKey ve sSubKeyName alanları bu çözümden gelir. Konsol ve GUI runner rollback aynı manifest yol çözümünü kullanır. Eski manifestlerde kök bilgisi yoksa HKLM varsayılır. Böylece rollback sırasında yeniden kullanıcı seçilmez.

Get-RemoteOpsRollbackChoices, RegistryRollback ve ServiceTaskRollbacks CSV kayıtlarından tarih/bilgisayar/değişiklik özeti üretir. ComboBox SelectedValue tam manifest yoludur; runner mevcut New-TargetScopedManifest ile hedef filtresini korur. Özet, kayıtlı işlem sonrası değer -> OldValue yönündedir. Değerin yokluğu ve boş string ayrıdır. Güncel hedef durumu sorgulanmaz. Bu v13 sözleşmesindeki REG_SZ sınırı v14 ile genişletilmiştir; onay sözcükleri korunur.

## v14: Tür bilgili registry veri sözleşmesi

Modules/RegistryValues.ps1 ortak codec, EnumValues ile tür tespiti, türüne uygun Get/Set metotları ve Restore-RemoteOpsRegistryEntry işlevini sağlar. Desteklenen tür kodları 1=REG_SZ, 2=REG_EXPAND_SZ, 4=REG_DWORD, 7=REG_MULTI_SZ, 11=REG_QWORD. EnumValues başarısızsa string okumaya geri dönülmez. Desteklenmeyen türler yedeklenmeden değiştirilmez veya silinmez.

CSV manifestlerine OldType, NewType ve DataEncoding=TypedText-v1 eklenir. OldValue/NewValue: metinlerde ham içerik, sayılarda kesin işaretsiz ondalık metin, MULTI_SZ'de JSON string dizisidir. UINT64 hiçbir aşamada kayan noktaya dönüştürülmez. SetDWORDValue/SetQWORDValue'ya uint32/uint64, SetMultiStringValue'ya string[] geçirilir. Değişiklikten önce eski tür ve veri kalıcı olarak yazılır. Runner ve konsol rollback aynı setter katmanını kullanır. Eski türsüz manifestlerin OldValue alanı REG_SZ olarak ele alınır. Yeni kayıtlı HKU SID davranışı korunur.

REG_EXPAND_SZ ham okuması RegistryKey.GetValue(..., DoNotExpandEnvironmentNames) ile yapılır; mevcut tür ayrıca ExpandString olarak doğrulanır. Uzak erişim runner kimliğiyle OpenRemoteBaseKey üzerinden gerçekleşir; bu erişim için Remote Registry gerekir. WMI GetExpandedStringValue yedek için kullanılmaz. Ham okuma hatası değişikliği engeller. HKCU önce kaydedilmiş HKU SID yoluna çözülür; operatörün yerel ortam değişkenleriyle genişletme yapılmaz.

GUI ValueType seçimini runner modüle -ValueType olarak geçirir. Auto varsayılandır; mevcut tür korunur, eksik değer REG_SZ olur. Açık tür mevcut türle çelişirse hata verir. Konsol çağrılarında yeni değer türü için Invoke-RegistryOperationsMenu -ValueType REG_QWORD gibi bir parametre kullanılabilir. Boş metin REG_SZ/REG_EXPAND_SZ için geçerlidir; sayısal taşma, eksi/kesirli sayılar ve string olmayan MULTI_SZ öğeleri reddedilir.

## v15: Salt okunur geçmiş ve teşhis

RemoteOps.History.ps1 Logs/Reports/Ledger ve Logs/Operations/<Operation>/<OperationID> kayıtlarını birleştirir. Ledger hedef sonuçları önceliklidir; CSV adımları özgün ayrıntıdır. Geçerli üretici adları Results/Error, <OperationID>_<bilinen operasyon adı> ve <OperationID>-access biçimleridir. Keyfi CSV/HTML dosyaları tanı arşivine alınmaz. Tarih/operasyon/hedef/durum filtreleri yereldir; her sayfa en çok 50 çalışmadır. Ayrıntılar seçimde yüklenir. İndeks ilk sekme girişinde veya Yenile ile taranır; 500ms zamanlayıcısına bağlı değildir. Çok büyük arşivlerde ilk indeksleme dosya sayısına bağlıdır.

RemoteOps.Diagnostics.ps1 hedefin özgün terminal sonucunu korur. Teşhis grupları kontrol önerileridir; bilinmeyen kod açıklaması üretilmez. 3010/1641 Success yanında da ayrıca görünür. Hedefsiz Error.csv '(çalışma)' kapsamındadır. Boş rapor HTML bağlantısı korunur. Eksik/bozuk dosyalar ayrı Issues kayıtlarıdır.

RemoteOps.HistoryUi.ps1 iki sekmeyi oluşturur. Seçim durumu canlı izleyiciden ayrıdır. Filtre dışı kalan seçim temizlenir. Kısa ekranda içerik kaydırılır. Dosya açmadan önce kapsam ve varlık yeniden doğrulanır. Hedef log/dosyaları yalnızca PulledLogs/<OperationID>/<ComputerName> ve PulledFiles/<OperationID>/<ComputerName> ile eşlenir; rapordaki dış LogDestination yolu izlenmez.

Tanı ZIP'i seçili rapor kökündeki bilinen sonuç raporları, Activity, RemoteOps.log, PackageDefinition.json ve Workers/<index>.out.log/.err.log dosyalarını içerir. Çekilen hedef dosyaları ve kişisel katalog/profiller kapsam dışıdır. Dizin geçişi ve reparse/junction reddedilir. Önizlemede SHA-256 alınır; export tekrar izin listesi/hash doğrular. Dosya okunurken yazma/silme paylaşımı verilmez. ZIP CreateNew ile üretilir; entry ve içerik hash'leri doğrulanır. Başarısız export kendi kısmi ZIP'ini temizler; mevcut ZIP silinmez. Logların hassas veri içermediği garantisi yoktur; kullanıcı paylaşmadan önce inceler.

Güncel kayıtlar V15_VALIDATION.json ve V15_TEST_RESULTS.csv içindedir. Tarihsel canlı testler bu teslimin şirket kabulü değildir. Drive yüklemesi kullanıcı istediğinde yapılır.

## v16: Hedef grubu ve önizleme sözleşmesi

TargetGroups.ps1 normalize hedefler, RemoteOps.TargetGroup/1 şeması ve kişisel CRUD sağlar. APPDATA/MDRemoteOps/TargetGroups/<GUID>.json altında Id, Revision, Name, Description, Targets, CreatedAt ve UpdatedAt saklanır. Yeni taslak revizyonu 0, ilk kayıt 1'dir. `.lock` FileShare.None kilidi ve beklenen revizyon kontrolünden sonra mevcut atomik JSON yazıcısı kullanılır. Eski revizyon, silinen kayıt, bozuk JSON, tür/şema/kimlik uyuşmazlığı ve reparse/junction yolları reddedilir. Grup onay veya credential içermez. Hedef tekilleştirmesi OrdinalIgnoreCase kullanır; IPv4/FQDN ve ASCII adlar kabul edilir; IPv6/joker/path desteklenmez.

TargetGroupsUi.ps1 yönetim sekmesini ve yeniden kullanılan picker'ı sağlar. Seçim salt okunurdur; yalnızca açık Ekle/Değiştir eylemi hedef metnini yazar. Her aktarım katalog kaydını ve revizyonu tekrar doğrular. Grup güncellemesi mevcut hedef metnine/çalışan isteğe yansımaz. Grup kaydetme ve seçim ağ operasyonu başlatmaz.

Preview.ps1 26 operasyon için etki, geri alma sınırı, yerel uyarılar ve bağımsız parametre snapshot'ı üretir. Canonical SHA-256 fingerprint; operasyon metadata'sı (ParallelSafe dahil), normalize hedefler, güvenli profil kimliği, parametreler, paket tanımı/revizyonu ve ilgili ayarları kapsar. Parola/ProtectedPassword ve onay metni halka açık modele alınmaz. Tanınmayan gizli/özel operasyon alanları gösterilmeden hash ile güncellik karşılaştırmasına katılır. Registry Auto, boş metin, çok satırlı veriler ve bool türleri korunur. Eklenti etkisi bilinmiyor diye belirtilir; güvenli işlem iddiası üretilmez.

PreviewUi.ps1 genel operasyon özetini oluşturur. UI Çalıştır önce önizlemeye gider; yalnızca onaylanan özet Start'ı mevcut Start-RemoteOpsRequest çağırır. Güncel form/hesap/ayar fingerprint'i eşleşmezse dispatch yapılmaz. Onay sözcüğü formdan tekrar okunur ve mevcut Start/Runner kontrollerinden geçer. Paketlerim mevcut özet panelinde ortak modeli kullanır. Paket başlatmada hem seçili kayıt hem disk kataloğu tekrar doğrulanır; eski/silinmiş paket genel saved-package akışında da reddedilir. Snapshot paralellik metadata'sını korur; gerçek dispatch'te ayar 1'e düşmez.

Yerel önizleme ağ erişimi/kurulu sürüm/sonuç tahmini değildir; canlı ön koşullar Runner'da tekrar kontrol edilir. Mevcut veri/profil yolları ve uzak yürütme motoru korunmuştur. Güncel testler V16_TEST_RESULTS.csv ve V16_VALIDATION.json; tarihsel v15 doğrulaması kendi sürüm kanıtıdır. Gelecek kapsam: birleşik geri alma merkezi, ardından reçeteler.


## v17 — Birleşik Geri Alma Merkezi

Geri Alma Merkezi sekmesi, DeleteBackups, FileRollbacks, RegistryRollback ve ServiceTaskRollbacks altındaki yerel manifestleri birlikte gösterir. Dosya/klasör geri yükleme, dosya taşıma/değiştirme geri alma, registry, servis ve zamanlanmış görev kayıtları desteklenir. Bir kayıt tek manifest, tek bilgisayar ve tek türdür; aynı kaydın bütün nesneleri kapsam içindedir. Farklı çalışmalar birleştirilmez. Süreç sonlandırma ve görev çalıştırma geri alınabilir gösterilmez.

Bilgisayar, tür, kullanılabilirlik ve tarih aralığıyla filtreleyin; sayfa başına 50 kayıt görünür. Bitiş tarihi günün tamamını kapsar. İlk sekme açılışı ve Yenile yerel dosyaları okur; arka planda sürekli tarama veya hedef sorgusu yapılmaz. Yerel yedeğin bulunması, hedefe erişim veya güncel durum garantisi değildir. Eksik/bozuk yedekler açıklamalarıyla görünür ve başlatılamaz.

Kaydı seçip Geri almayı önizle düğmesini kullanın. Gerçek çalıştırma hesabı, bilgisayar, bütün nesneler ve kaydedilen eski durum gösterilir. Dosya geri yüklemede RESTORE, diğer türlerde ROLLBACK sözcüğünü yazarak İnceledim, başlat düğmesine basın. Vazgeç işlemi başlatmaz. Önizleme sonrası hesap, ilgili ayarlar, manifest, kayıt kapsamı veya gerekli yedeğin kontrol edilen kimliği değişirse yeniden önizleme gerekir. Runner hedefte değişiklikten önce seçimi tekrar doğrular; liste sıra numarası kullanılmaz.

Dosyalar geri kopyalanırken aynı adlı hedeflerin üzerine yazılabilir. Klasör geri yükleme hedefteki fazladan dosyaları silmez. Dosya taşıma geri almada kaynak, manifestte kaydedilen taşınmış konumdur. Registry türü ve kaydedilmiş HKU SID yolu korunur; eksik değer ile açıkça kaydedilmiş boş metin ayrılır. Servislerde kaydedilen eski durum/başlangıç türü uygulanır. Silinen görev XML yedeğinden oluşturulur, aynı adlı mevcut görev ezilmez. DTD ve dış kaynak çözümleme kapalıdır.

Bu sürüm tümünü geri al, otomatik zincir, otomatik tekrar deneme veya nesne bazında kapsam daraltma içermez. Mevcut Operasyon sekmesindeki geri alma girişleri korunur. Çalıştırma çıktıları mevcut rapor ve Geçmiş akışına gider. Uzun ömürlü dosya yedeklerinin bütün içerikleri indekslemede hash'lenmez; manifest SHA-256 ve yedek meta verisi, görev XML hash'i, yol ve reparse kontrolleri uygulanır. Bu, dosya yedeğinin tamamına kriptografik bütünlük veya işlem atomikliği garantisi vermez.

![Geri Alma Merkezi — örnek verili gerçek WPF](screenshots-v17/geri-alma-merkezi.png)

![Geri alma önizlemesi — örnek verili gerçek WPF](screenshots-v17/geri-alma-onizleme.png)

Görseller yerel fixture verileridir. v17 kapsamında gerçek şirket bilgisayarında uzak geri alma testi yapılmamıştır. Sürüm ayrı klasörde ve doğrulanmış ZIP ile teslim edilir; bu aşamada Drive yüklemesi yapılmaz.


## v18 — Operasyon reçeteleri

Dokuzuncu sekme Operasyon Reçeteleri, servis/dosya/registry/paket adımlarını sıralı bir kişisel tarifte birleştirir. Yeni ile ad/açıklama girin; Adım ekle ile 1–20 işlem oluşturun. Adımı seçip alanlarını düzenleyin, Yukarı/Aşağı ile sıralayın ve Kaydet kullanın. Sağ panel bütünüyle kaydırılır; küçük ekranda alt bölümdeki kaydetme ve çalıştırma alanlarına kaydırarak erişilir. Kopyala yeni kimlikli taslak hazırlar; Tanımı sil yalnız kişisel tarifi kaldırır.

İlk izin listesi: servis listeleme/kontrol/başlangıç türü; dosya gönderme/karşılaştırma/yedekli silme; registry okuma/düzenleme/silme ve kayıtlı paket dağıtımı. Serbest kod, eklenti, iç içe tarif, koşullu dal ve adımlar arası çıktı değişkeni yoktur. Reçeteler %APPDATA%/MDRemoteOps/Recipes altında şema/revizyonla tutulur. Hesap, hedefler, parola ve çalıştırma onayı tanımda saklanmaz.

Kayıtlı paketin tam tanımı reçeteye kopyalanır. Paket kataloğu sonradan değişirse eski reçete sessizce değişmez; güncellemek için adımda paketi yeniden seçip reçeteyi kaydedin. Hedefleri çalışma alanında yazın veya hedef grubunu Ekle/Değiştir ile kullanın. Reçeteyi önizle hesabı, hedefleri, sıralı bütün parametreleri ve etkileri gösterir. Her yeni çalıştırmada RECETE yazılır. Kaydedilmemiş düzenleme, değişmiş kayıt/hesap/hedef/ayar eski önizlemeyi geçersiz kılar.

Bilgisayarlar sırayla, her bilgisayarın adımları sırayla çalışır. Normal bir adım hatasında o bilgisayarın kalan adımları NotRun olur; sonraki bilgisayara geçilir. Dosya karşılaştırmada Farkli veya Bulunamadi zinciri durdurur. Dosya gönderirken atlanan dosyalar tamamlanmış sayılmaz. Servis listesinde eşleşme olmaması veya registry okumada değerin yokluğu bilgi olarak korunabilir; yazma hatasıyla karıştırılmaz. Paketin doğrulanmış zaten mevcut/yok/hedefte atlaması devam edebilir; genel Skipped devam izni değildir. Yeniden başlatma gereksinimi zinciri durdurur.

Durdur isteği bütün yeni adım/hedefleri engeller; aktif alt adımın sonucu beklenir. Zorla durdurmak yerel süreç ağacını sonlandırır; uzak işlemin durduğunu garanti etmez. Sonucu bilinmeyen aktif adım Indeterminate olarak, özgün adım ve bilgisayar kimliğiyle kaydedilir. Otomatik retry/resume/reboot/rollback yapılmaz.

Bir alt adım 7200 saniyelik bekleme eşiğini aşarsa yeni işler engellenir ve aktif yerel süreç takip edilmeye devam edilir. Süreç kendiliğinden bitene veya kullanıcı açıkça zorla durdurana kadar çalışma görünür kalır; başka hedefe gizlice geçilmez. Geçerli geç sonuç özgün satırlarda korunur; eşiği aşan reçete otomatik devam etmez. Bu eşik uzak işlemi otomatik öldüren bir süre sınırı değildir.

Uygulama yeniden açıldığında yalnız kesilmiş reçete checkpoint'leri yerel rapora dönüştürülür. PID ve süreç başlangıç zamanı hâlâ eşleşen Runner'a dokunulmaz. Başlamış fakat tamamlandığı kanıtlanamayan adım belirsizdir; başlamamış adımlar NotRun olur. Bu işlem hedefte reçeteyi sürdürmez ve ayrı yarım kalan işler merkezi eklemez.

Geçmişte reçete tek üst çalışma olarak görünür. Paket / reçete sütunu tarif adını gösterir; hedef başına tek terminal sonuç ve ayrıntıda özgün adım kimlikleri/çıktıları vardır. Alt süreçler günlük ledger'a ayrı çalışmalar eklemez. Teşhis özgün hata/exit code bilgisini korur. Servis/registry/yedekli silme manifestleri mevcut Geri Alma Merkezi'nde bulunabilir; tüm reçeteyi tek eylemle geri alma yoktur.

Dosya gönderme aynı adlı içeriği ezebilir ve otomatik yedek/geri alma sağlamaz. Örneğin servis durdurulduktan sonraki dosya adımı hata verirse sonraki servisi başlat adımı çalışmaz; önceki değişiklikler otomatik geri alınmaz. Yerel önizleme canlı hedef durumunu veya kaynak erişimini garanti etmez. Üst ve alt istekler 22000 Base64 karakter sınırına tabidir; çok büyük tarif açık hatayla reddedilir, kesilerek çalıştırılmaz.

![Operasyon Reçeteleri — örnek verili gerçek WPF](screenshots-v18/operasyon-receteleri.png)

![Reçete önizlemesi — örnek verili gerçek WPF](screenshots-v18/recete-onizleme.png)

Doğrulamalar yerel fixture, sahte uzak çağrılar ve gerçek WPF/Runner süreçleriyle yapıldı. v18 için gerçek şirket hedefinde canlı işlem yapılmadı. Dağıtım v18 klasörü ve doğrulanmış ZIP'tir; v17 korunur, Drive yüklemesi yapılmaz.


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
