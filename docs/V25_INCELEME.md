# v25 kullanılabilirlik düzeltmesi ve doğrulama

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


## Doğrulama yaklaşımı

Yeni ConditionAuto testleri, gerçek hedef yerine sahte okuma nesneleriyle sayı1, metin1, sürüm16.0.444, QWORD sınırları, hex, bozuk hedef/hatalı beklenen ayrımı, çok satırlı metin ve hata baskınlığını sınar. ConditionAutoExecution şema3, eski şema2, hedefe özel koşullu adım ve kanıt doğrulamasını birlikte sınar. Mevcut gerçek yerel alt süreçli ConditionRunner testi korunur; uzak sınırlar sahtedir.

ConditionFriendlyUi gerçek WPF testi, Adım ekle girişini, ilgili alanların görünürlüğünü, registry türü alanı olmadığını, Türkçe servis seçiminin doğru sistem kodunu tuttuğunu, eski türün değişmeden kaydedildiğini ve beklenen değer düzenlenince otomatiğe geçildiğini doğrular. Geçersiz işlem/koşul dönüşümleri bağlı adımların kapsamını bozamaz. V24 ConditionUi testi yeni gerçek kullanıcı girişini kullanacak şekilde güncellendi.

Bağımsız incelemede core ve arayüz için engelleyici bulgu bulunmadı. Özel ek WPF kontrollerinde ortadaki bağlı adımı koşula veya bağlı işlemleri olan koşulu normal işleme çevirmenin bağlantıları bozmadığı doğrulandı. Tüm sonuçlar V25_TEST_RESULTS.csv ve V25_TEST_SUMMARY.json; son yeniden çalıştırmalar V25_RERUN_RESULTS.csv içindedir. Canlı şirket kabul testi ve Drive yüklemesi yapılmadı.
