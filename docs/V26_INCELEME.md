# v26 teslim ve inceleme kaydı

15 Ekim 2026 · YD_RemoteOps.App_v26

## Değişiklik

Reçete ekranındaki uzun işlem formu kaldırıldı. Ana sayfada reçete adı, isteğe bağlı açıklama, esneyen adım listesi ve sabit komut alanı var. Hedefler ayrı sekmede. Adım ekleme/düzenleme ayrı pencerede açılır; İşlem ve Çalışma koşulu sekmeleri bulunur. Koşul ayrı bir yeni adım türü olarak seçilmez. Adım listesi koşulun özetini ilgili işlemin altında gösterir.

Yeni adımların adı işlemin alanlarından otomatik üretilir; özel ad isteğe bağlıdır. Üretilen adlar kayıt sınırına uygun kısaltılır. Mevcut özel adlar, otomatik üretilebilecek metinle aynı olsalar bile korunur. Yeni Recipe/4 biçimindeki AutoName boolean bilgisi otomatik adlandırma seçimini yeniden açıldığında da korur. Eski Recipe/1, /2 ve /3 kayıtları değiştirilmeden açılıp okununca aynı kalır; otomatik isimlendirme istendiğinde yeni biçim gerekir. v25 ve daha eski uygulamalar Recipe/4 kayıtlarını açamaz; eski dağıtımlar korunur.

Yeni koşul ilgili işlemden yönetilir. İçeride mevcut RecipeCondition/ConditionId yürütme modeli kullanılır. Eski ortak koşullar ayrı adımlara kopyalanmaz; bir kez değerlendirilip eski bağlı kapsamına uygulanır. Ortak grup düzenleyicide açıkça belirtilir ve grup birlikte taşınır. Ortak gruptan tek adım silme engellenir. Yeni tek işlem koşulu ve işlem birlikte taşınır/silinir. Düzenlemeden vazgeçmek taslağı geri getirir.

Registry gerçek türünü okuyan otomatik karşılaştırma, servis kontrolleri, All/Any, hata durumunda durdurma ve çalışma önizlemesindeki RECETE onayı korunur. Runner, koşul değerlendirme, reçete yürütme ve sonuç modülleri önceki sürümle aynıdır. Runtime C:\Temp\YD_RemoteOps.App ve AppData katalog/profil yolları değişmedi.

## Doğrulama kapsamı

- Tüm yerel testlerin sonuçları V26_TEST_RESULTS.csv ve V26_TEST_SUMMARY.json içindedir. Bunlar test dosyası sayısıdır, tekil assertion sayısı değildir.
- Bağımsız uyumluluk testi eski üç biçimde birebir hash, özel isimler, iptal, otomatik isimlerin yeniden açılışı, ortak koşulun bir kere değerlendirilmesi ve grup hareketini sınar.
- Gerçek WPF ana ekran ölçümü 1280x810, 1060x700 ve 960x550 boyutlarında adım ekle, reçete adı, kaydet ve önizlemeye sayfa kaydırmadan erişildiğini kontrol eder. Uzun listeler kendi alanında kaydırılabilir. Çok sayıda kontrol veya olağandışı küçük pencere durumunda düzenleme alanının kendi kaydırması kullanılabilir.
- Normal ve 125 yüzde çizim ekranları screenshots-v26 içindedir. Bunlar yalıtılmış örnek verili gerçek WPF çizimleridir; canlı uç nokta ekranları değildir.
- Gerçek uzak hedef bağlantısı veya değişikliği yapılmadı. Uzak işlem testleri taklit sınırlar kullanır. Şirket ortamında canlı kabul testi yapılmış sayılmaz.
- Son ZIP için CRC ve arşivdeki her dosyanın kaynakla SHA256 eşitliği doğrulanır; dış doğrulama kaydı ZIP yanında tutulur. v25 kaynak ve ZIP değişmeden korunur. Drive yüklemesi istenmedi/yapılmadı.

## Sınırlar

Koşul ve işlem arasında hedef durumu değişebilir; atomik işlem veya otomatik geri alma eklenmedi. Wire biçiminde koşullar dahil toplam 20 adım, koşul başına 10 kontrol, tek seviye ve kesintisiz bağlı kapsam sınırı devam eder. Eski ortak koşulların işlemlere ayrılarak tekrar değerlendirilmesi yapılmaz.
