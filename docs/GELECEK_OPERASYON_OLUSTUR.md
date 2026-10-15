# Operasyon reçeteleri ve gelecek geliştirmeler

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


15 Ekim 2026 · YD_RemoteOps.App_v25

## Mevcut kapsam

v18 ile izin verilen hazır operasyonlardan 1–20 adımlı kişisel reçete oluşturma, revizyonlu kaydetme/kopyalama, kayıtlı paket snapshot, hesap/hedef önizleme ve yeni RECETE onayı uygulandı. Hedef ve adımlar sıralıdır; hata sonrası o hedef durur. İptal/checkpoint, yeniden açılışta rapor onarımı, tek üst geçmiş ve adım teşhisi mevcut altyapıya bağlandı.

## Örnek akış

1. OrnekServis servisini durdur.
2. Ayar dosyasını gönder.
3. Servisi başlat.

Bu örnekte ikinci adım hata verirse üçüncü adım başlamaz; otomatik servis kurtarma yapılmaz. Dosya gönderme üzerine yazabilir ve otomatik yedek sağlamaz. Örnek şirket hedefinde denenmiş kabul edilmez.

## Gelecekte değerlendirilecekler

Koşullu dallanma, adımlar arası çıktı değişkenleri, paylaşılmış ekip kataloğu, import/export, merkezi hedef kilidi ve otomatik kurtarma şu an yoktur. Serbest kod ve iç içe tarif de desteklenmez. Bu alanlar şirket pilotu ihtiyaçlarıyla ayrıca tasarlanmalıdır. Kademeli dağıtım bütün operasyonlara yayılmaz; ayrı sekme henüz uygulanmadı.

## Mevcut sınırlar

Aynı hedefe farklı operatörlerin eşzamanlı iş başlatmasını bütün operasyonlarda engelleyen merkezi kilit yoktur. Reçete kendi içinde sıralıdır. Yerel önizleme canlı durum sorgusu değildir. Büyük istekler 22000 Base64 sınırında açık hatayla durur. İptal/timeout uzaktaki işlem kesin durdu demek değildir. Ayrıntılı kullanım ve etkiler kullanım kılavuzundadır.


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
