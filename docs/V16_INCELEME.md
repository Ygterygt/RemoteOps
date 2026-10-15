# v16 inceleme ve teslim özeti

15 Ekim 2026 · YD_RemoteOps.App_v16

## Teslim kapsamı

Kişisel, revizyonlu hedef grupları; Hedef Grupları yönetim sekmesi; paket/operasyon hedef alanlarında açık Ekle/Değiştir eylemleri; genel işlem önizlemesi ve paketlerde ortak modelle genişletilen mevcut dağıtım özeti eklendi. Önizleme salt yerel hazırlıktır; hedefin erişimini veya kurulu sürümünü bildiğini iddia etmez. Yürütme ve onay kontrolleri mevcut Runner'da korunur.

## Doğrulama

Başlangıç mevcut 60 test dosyası geçti. Dört yeni dosya TargetGroups, Preview, TargetGroupsUi ve PreviewUi ile son regresyon 64 test dosyasını kapsar. Tam sonuçlar V16_TEST_RESULTS.csv, çıktılar v16-test-logs, parser kayıtları V16_PARSE_RESULTS.csv ve hash manifesti V16_VALIDATION.json içindedir. Test sayısı test dosyasıdır; gerçek hedef veya tekil assertion sayısı değildir.

Yeni fonksiyonlar ve arayüzler testler yazılıp eksik özellik hatası görüldükten sonra uygulandı. Hedef/culture/IPv4/FQDN doğrulaması, revizyon/CRUD/silinmiş kayıt, credential alanı reddi, Ekle/Değiştir, 26 operasyonun etki açıklaması, değişmez snapshot, profil/parametre/hedef/ayar/paket değişikliği reddi ve gerçek WPF olayları sınandı. Var olan paket, katalog, startup ve NoUi testleri yeni UI bağımlılıklarıyla güncellendi; gerçek uzak worker argüman kontrolleri korunur.

## İnceleme ve düzeltmeler

Bağımsız salt okunur inceleme üç Important bulgu verdi: paket yenilemesinde tekrar eklenen grup seçicileri, önizleme sonrası ParallelSafe metadata kaybıyla paralelliğin 1'e düşmesi ve genel saved-package akışında disk kaydının yeniden okunmaması. Üçü de hatayı yeniden üreten testlerle düzeltildi. Grup editörünün açık Yenile eyleminde güncel revizyonu yüklememesi de başarısız testle gösterilip düzeltildi. İlk geniş turdaki katalog kontrolü yeni Önizle düğmesinin ana ad bağlama listesine eklenmesi gerektiğini yakaladı; standart bağlama düzenine alındı.

Parolalar halka açık önizlemeye alınmaz. Sadece kaydedilmiş parola değişikliğinin güvenli profil kimliği fingerprint'ini değiştirmemesi tasarım kararıdır; runtime credential doğrulaması korunur. Grup normalizasyonu ordinaldir; seçim hedefi otomatik değiştirmez. Tek başarılı özet ikinci kez başlatılamaz; onay sözcüğü çalıştırma anında formdan alınır. Registry boş/çok satırlı veriler ve bool parametreleri snapshot'ta korunur.

## Görseller ve sınırlar

screenshots-v16 gerçek WPF kontrollerinde yapay TEST/PC-IST verileridir. Normal ve 1366x768/yüzde 125'e karşılık gelen küçük içerik alanları incelendi. Kaydet/başlat düğmeleri erişilebilir; form/uzun özet kaydırılır. Gerçek şirket hedefinde bağlantı, kurulum veya mutasyon yapılmadı. Önceki v10/v11 canlı kanıtları tarihsel kayıttır.

Hedef grupları kişiseldir; merkezi katalog ve import/export yoktur. IPv6/joker/path hedef biçimleri desteklenmez. Önizleme canlı salt okunur ön kontrol içermez; ağ ve uygulama durumunu Runner yürütme sırasında denetler. Büyük hedef listeleri mevcut istek boyutu sınırına tabidir; aşılırsa mevcut başlatıcı reddeder. Yeni gruplar bu sınırı artırmaz. Birleşik geri alma merkezi ve reçete motoru sonraki teslimlerdir.

## Teslim kararı

Git deposu olmadığı için v15 korunarak kardeş v16 kopyası, test kayıtları ve hash doğrulaması kullanıldı; commit düzeyinde geri dönüş yoktur. Mevcut runtime ve APPDATA profil/katalog yolları korunur. Yeni hedef grupları APPDATA/MDRemoteOps/TargetGroups altındadır. v16 doğrulanmış ZIP olarak teslim edilir; Drive yüklemesi yapılmadı.
