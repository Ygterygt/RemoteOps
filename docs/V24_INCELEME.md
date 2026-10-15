# v24 doğrulama ve kapsam

15 Ekim 2026 · YD_RemoteOps.App_v24

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


## Doğrulama yöntemi

Yeni Conditions, ConditionExecution, ConditionUi ve ConditionRunner testleri: tür korumalı registry karşılaştırması, tam servis adları, Tümü/Herhangi biri doğruluk tabloları, hata baskınlığı, gerçek WPF düzenleme/kaydetme/kopya/sıralama kapsamı, hedef başına atla/dur, onaylı kanıta bağlı karar ve değişmiş snapshot reddi. ConditionRunner gerçek yerel koordinatör ve alt süreçleri sahte registry/servis sınırlarıyla çalıştırır; yalnızca izin verilen örnek hedefteki sahte StartService çağrısı kaydedilir. Gerçek uzak bilgisayara bağlanmaz.

Bağımsız incelemede eksik sağlayıcı alanlarının yanlışlıkla yok/0 sayılması ve yetersiz koşul kanıtının kabul edilmesi bulundu. Koşula özel katı okuyucu, denetim kimliği/değer eşleştirmesi ve okunan kanıttan kararın yeniden hesaplanması eklendi. İlgili regresyonlar düzeltme öncesi başarısız, düzeltme sonrası başarılı oldu. Eski registry modülleri değişmedi.

Mevcut Recipe/1 ve eski RecipeUi/RecipeExecution testleri korunur. Tüm sonuçlar V24_TEST_RESULTS.csv, V24_TEST_SUMMARY.json; son yeniden çalıştırmalar V24_RERUN_RESULTS.csv içindedir. Uzak canlı kabul testi yapılmadı. Kişisel hesaplar, runtime ve AppData kökleri korunur. v23 dağıtımı ve ZIP dosyası korunur; Drive yüklemesi istenmedi.
