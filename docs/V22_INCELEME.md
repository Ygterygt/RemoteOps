# v22 — Tek operatör arayüzü

15 Ekim 2026 · YD_RemoteOps.App_v22 · Önceki sürüm v21

Gruplu sol menü mevcut dokuz TabItem ve olay işleyicisini kullanır. Düğmeler ile programatik geçişler aynı seçime bağlıdır. Başlık VERSION.json kaydından sürümü okur. Mevcut ekranlar, profil seçimleri, paket düzenleme geçişleri ve alt izleme alanı korunur.

Teşhis nedeni ve sonraki adım ayrı kartlara taşındı. Özgün metin teknik ayrıntılar içinde korunur. Geri almada yerel yedek, sonuç kaydı ve sorgulanmamış hedef durumu ayrı gösterilir; seçim temizlendiğinde kartlar temizlenir. Geri alma filtreleri etiketlendi; liste ve ayrıntı arasına genişlik ayırıcı eklendi.

Tek operatör kapsamı: ekip kataloğu, çok kullanıcılı onay ve operatörler arası merkezi kilit eklenmedi. Uzak yürütme/geri alma motoru değiştirilmedi.

## Doğrulama

Yeni gerçek WPF regresyon testi önce eksik gezinme nedeniyle başarısız oldu. Dokuz hedefe düğmeyle geçiş, programatik geçişin menüyle eşleşmesi, sürüm başlığı, boş kart durumu ve yeni iş başlatılmaması sınanır. Mevcut katalog testi, pencere şablonundaki kontrollerin ayrı şablon ad alanından çözüldüğünü doğrulayacak şekilde genişletildi.

Tüm test sonuçları V22_TEST_RESULTS.csv ve V22_TEST_SUMMARY.json içindedir. Bunlar yerel testler ve sahte uzak sınırlar içerir; canlı şirket kabul testi değildir. Ekranlar yalıtılmış AppData ve veri kökünde örnek verilerle gerçek WPF çizimidir. Normal, yüzde 125 ve 960×550 içerik boyutları incelenir. PDF kılavuzları yeniden üretilir ve sayfa görselleri kontrol edilir.

![Teşhis](screenshots-v22/hata-teshisi.png)

![Geri alma](screenshots-v22/geri-alma.png)

## Sınırlar

Gerçek uzak hedef testi ve Drive yüklemesi yapılmadı. Önizleme güncel hedef sorgusu değildir. Dar pencerede menü ve içerik kaydırılır. Önceki sürümlerin ekranları tarihsel belge olarak korunur. v21 kaynak ve ZIP dosyaları korunur.
