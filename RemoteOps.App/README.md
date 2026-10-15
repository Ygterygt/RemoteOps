# YD RemoteOps v28

Tek operatör için Windows PowerShell 5.1 ve WPF uzak operasyon paneli.

v28: Servis/registry/dosya gönderiminde otomatik son durum kontrolü; komut yanıtı ve doğrulamanın ayrı gösterildiği adım sonuçları. Mevcut Recipe/1..4 korunur. Beklenen durum oluşmazsa veya doğrulanamazsa o hedefin sonraki adımları durur. Önceki işlemler otomatik geri alınmaz. [v28 kullanım ve test kapsamı](../docs/V28_TEST_RAPORU.md).

Hafif test paketi: kökte HAFIF_TEST_CALISTIR.bat. Canlı hedeflere bağlanmadan yerel kaynaklar ve SIM modeli kullanır.

Aşağıdaki önceki sürüm özellikleri korunur.

Başlatma: dağıtım kökündeki YD_RemoteOps.App.bat. Modules, RemoteOps.App ve PsExec.exe birlikte tutulmalıdır.

Sol menü: Çalıştır, Hazırla, İncele ve Kurtar. Mevcut dokuz ekran korunur. Teşhis ve geri almada özet kartları, açılır teknik ayrıntılar, sürüm bilgisi ve kompakt üst başlık bulunur. Profiller aynı operatörün farklı çalışma hesaplarıdır.

Runtime C:\Temp\YD_RemoteOps.App, kataloglar/profiller %APPDATA%\MDRemoteOps altında kalır.

[Kullanım kılavuzu](../docs/KULLANIM_KILAVUZU.md) · [v26 doğrulama](../docs/V26_INCELEME.md)

Yerel testler ve örnek verilerle WPF çizimleri canlı şirket testi değildir. Bu teslimde canlı uzak hedef değişikliği ve Drive yüklemesi yapılmadı.


Üç ekranda ortak hedef sayımı/düzenleme, izleme ve geçmişte sonuç filtreleri, seçili sonuçtan doğru teşhis ve bilgisayar yedeklerine geçiş korunur. Liste düzenleme ve gezinme hedefte iş başlatmaz.


Registry/servis koşulları, Tümü/Herhangi biri grupları, adımı atlama/hedefi durdurma seçenekleri korunur. Recipe/1, /2 ve /3 mevcut kayıtları açılır. Otomatik adlandırma tercihi Recipe/4 biçiminde saklanır ve v26 gerektirir.


Registry türü hedefte otomatik okunur; servis kontrolleri yalnızca ilgili alanları gösterir. Eski ortak koşulların tek değerlendirme ve kapsam davranışı korunur.

## v26 reçete düzenleyicisi

Koşullar ilgili adımın içinde düzenlenir. Adım adları otomatik oluşur; mevcut özel adlar korunur. Ana sayfa sabit komut alanı ve esneyen liste kullanır. İşlem ve koşul ayrı düzenleme penceresindedir. Adımlar ve Hedefler ayrı sekmelerdedir. Özel ad yalnızca isteğe bağlıdır. Önizleme ve RECETE çalışma onayı devam eder.
