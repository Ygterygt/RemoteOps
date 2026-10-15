# v23 doğrulama ve kapsam

15 Ekim 2026 · YD_RemoteOps.App_v23

## v23 — Ortak hedefler, sonuç filtreleri ve geçişler

Tek operatör için ikinci aşama. Paketlerim, Operasyon ve Operasyon Reçeteleri ekranlarında aynı hedef araçları bulunur. Seçili tekil hedef ve tekrar sayısı giriş sırasında güncellenir. Tekrarları temizle ilk yazılan adı koruyarak listeyi düzenler; geçersiz ad varsa girdi değişmez. Hedefleri düzenle penceresinde bilgisayar arayın, bir veya birden fazla hedefi seçip çıkarın ve Listeyi uygula ile kaydedin. Arama yalnızca görünümü süzer; aramada görünmeyen hedefler korunur. Vazgeç değişiklikleri uygulamaz. Açık pencere sırasında asıl hedef alanı değişirse eski liste uygulanmaz.

Hedefler üç ekran arasında otomatik eşitlenmez ve diske yeni bir ortak hedef listesi yazılmaz. Hedef gruplarına git kaydedilmiş kişisel listelerin ekranını açar; grubu hedef alanına aktarmak için dönüp Ekle/Değiştir seçilir. Her çalıştırmada mevcut önizleme ve onaylar geçerlidir.

Devam eden işler ve sonuçlar panelinde bilgisayar adı ve özgün sonuç kodu birlikte filtrelenebilir. Görünen / toplam hedef sayısı gösterilir; Filtreleri temizle bütün satırları geri getirir. Kaynak sonuç ve raporlar değişmez. İlerleme yenilenirken seçim çalışma ve bilgisayar kimliğiyle korunur; gizlenen satırın eski eylemleri açık kalmaz. Geçmiş ekranında hedef tablosu için ayrıca bilgisayar/sonuç filtresi vardır. Çalışma filtresi ile hedef filtresi ayrı kapsamları süzer.

Seçili sonucu teşhis et, ilgili çalışmanın rapor kökü ve hedefi eşleşiyorsa doğru teşhisi açar. Rapor henüz oluşmadıysa açıklama gösterilir. İzleme, Geçmiş ve Hata Teşhisi ekranlarından seçili bilgisayarın yedeklerine geçilebilir. Bu geçiş Geri Alma Merkezi filtrelerini ilgili bilgisayara ayarlar, önceki tür/tarih filtrelerini temizler ve bir geri alma kaydını otomatik seçmez. Hedefe bağlanmaz; geri alma başlatmaz.

![Ortak hedef seçimi](screenshots-v23/ortak-hedefler.png)

![Hedef listesini düzenleme](screenshots-v23/hedef-duzenle.png)

![Sonuç filtreleri](screenshots-v23/sonuc-filtreleri.png)

Bu teslimde uzak motor, çalışma hesapları, C:\Temp\YD_RemoteOps.App ve AppData yolları korunur. Gerçek uzak hedef testi yapılmadı. Ekranlar örnek verilerle gerçek WPF çizimidir. Aşağıdaki eski sürüm bölümleri ve ekranlar tarihsel bilgi olarak korunur.


## Doğrulama yaklaşımı

V23Workflow gerçek WPF testi: ortak hedefler, geçersiz adlar, tekrar temizleme, satır çıkarma, değişen hedef alanına eski düzenlemenin uygulanmaması, operasyon alan kimliğinin korunması, bileşik sonuç filtreleri, kaynak satırların korunması, seçimin ilerleme yenilemesinde korunması, raporu olmayan teşhis kısayolu, doğru rapor/hedef teşhisi, Geçmiş hedef filtresi ve bilgisayar yedeklerine geçiş. Yeni test önce ortak hedef araçları yokken başarısız oldu. Operasyon alan kimliği ve ilerlemede seçim kaybı için de düzeltme öncesi başarısız, sonrası başarılı regresyon görüldü.

Eski V22 sürüm testi VERSION.json içindeki güncel sürümü kontrol edecek şekilde güncellendi. Tüm yerel testler V23_TEST_RESULTS.csv ve V23_TEST_SUMMARY.json içinde; yeniden çalıştırmalar ayrı loglarda saklanır. Uzak motor ve Modules içerikleri v22 ile aynı kalır.

Bağımsız inceleme ilerlemede seçim kaybını belirledi; çalışma/bilgisayar kimliğiyle koruma eklenip regresyon testiyle doğrulandı. Canlı şirket kabul testi ve Drive yüklemesi yapılmadı. ZIP son doğrulamadan sonra oluşturulur ve her dosya karşılaştırılır.
