# RemoteOps paket yönetimi geliştirme planı

Tarih: 12 Ekim 2026

Güncel çalışma sözleşmesi [teknik el kitabında](TEKNIK_EL_KITABI.md), operatör adımları [kılavuzda](KULLANIM_KILAVUZU.md), temizlik/yeniden adlandırma sonrası test durumu [inceleme raporunda](INCELEME_RAPORU.md) bulunur. Bu dosya uygulanmış tasarımın karar kaydıdır.

Durum: Onaylanan tasarım uygulandı. Yerel testler ve kod incelemesi tamamlandı. 14 Ekim pilot geri bildirimi işlendi; tam şirket kabul matrisi bekleniyor. Günlük raporda paket/eylem bazında ayrı dağılım da tamamlandı; eski test envanteri güncel dağıtıma uyarlandı.

## Amaç ve kapsam

Şirket bilgisayarlarında yazılım dağıtırken aynı UNC yolu, paket dosyası, uygulama kimliği ve sürüm bilgilerinin tekrar girilmesini azaltmak. Operatör paketi bir kez tanımlayacak, Paketlerim ekranından seçip hedef bilgisayarları ve çalıştırma hesabını belirleyerek kuracak, kaldıracak veya eski sürüme döndürecek.

Windows PowerShell 5.1, WPF, mevcut profil sistemi ve ayrı Runner süreçleri korunacak. İlk sürümün odağı kaydedilebilir paket tanımları ve doğrulanan downgrade olacak. Genel amaçlı çok adımlı Operasyon Oluştur motoru ayrı bir sonraki kapsamdır.

Paket Oluştur, hazır dağıtım dosyalarını UNC üzerinden tanımlama anlamında kullanılır. MSI, EXE veya dağıtım scriptini sıfırdan üretmek bu ilk kapsamda değildir. Mevcut .bat, .cmd, .ps1 ve .vbs çalıştırma desteği kullanılır.

## Kullanım akışı

1. Paket Oluştur sekmesinde uygulama adı, sürüm ve çalıştırma tanımları girilir.
2. Kayıt doğrulanır ve Paketlerim listesine eklenir. Kaydetmek uzak bilgisayarda işlem yapmaz.
3. Paketlerim listesinden kayıt seçilir; Kur, Kaldır veya Eski sürüme dön eylemi seçilir.
4. Operatör hedefleri, hesabı ve eşzamanlı bilgisayar sayısını belirler.
5. Özet ekranında paket, işlem, hedef sürüm, hesap ve hedef sayısı gösterilir. Mevcut işlem onayları korunur; downgrade için DOWNGRADE kullanılır.
6. Runner paket tanımının çalışma anındaki kopyasıyla işlemi yürütür. Sonradan yapılan katalog değişiklikleri aktif çalışmayı değiştirmez.
7. Hedef ve adım sonuçları canlı görünür; bitişte sonuç raporu ve günlük rapor kaydı oluşur.

## Paket kaydı

Bir kayıt belirli bir uygulamanın belirli bir hedef sürümünü temsil eder. Desteklenen eylemler kayıtta ayrı ayrı tanımlanır. Aynı uygulamanın farklı sürümleri ayrı kayıtlar olarak tutulabilir; Kopyala eylemi yeni sürüm tanımlamayı kolaylaştırır.

| Alan | Davranış |
| --- | --- |
| Paket adı | Listede görünen anlaşılır ad |
| Kategori ve açıklama | Arama ve kullanım bağlamı |
| Hedef sürüm | Sürüm kontrollü kurulum ve downgrade için zorunlu |
| Kurulum kimliği | DisplayName exact, DisplayName contains veya ProductID; isteğe bağlı kesin registry anahtarı |
| Kurulum tanımı | UNC klasörü ve dosya adı |
| Kaldırma kimliği | Kaldırılacak uygulamanın kimliği; kurulum kimliğinden farklı olabilir |
| Kaldırma tanımı | Ayrı UNC klasörü ve dosya adı |
| Kontrol modu | Mevcut sürüm kontrollü, varlık kontrollü ve kontrolsüz davranışlar; downgrade her zaman kontrollü |
| Desteklenen eylemler | Gerekli alanları tamamlanan Kur, Kaldır ve Eski sürüme dön eylemleri |
| Log toplama | Paket için varsayılan; kullanıcı adıyla log temizleme mevcut genel ayarlara bağlı |
| Kayıt kimliği ve revizyon | Düzenleme, içe aktarma ve çalışmada kullanılan tanımı izleme |
| Oluşturma ve güncelleme tarihleri | Paket bakımını takip etme |

Kimlik alanları tek bir metin kutusuna sıkıştırılmaz. Kaldırılacak sürümün ProductID'si, kurulacak eski sürümün ProductID'sinden farklı olabilir. Çoklu eşleşmede otomatik uygulama seçimi yapılmaz; kesin anahtar veya kimlik gerekir.

Hedef bilgisayarlar, parola ve onay kelimesi paket kaydına yazılmaz. Hesap her çalıştırmada mevcut profil sisteminden seçilir. Eşzamanlı bilgisayar sayısı mevcut genel ayardan gelir.

İlk katalog kullanıcıya ait `%APPDATA%\MDRemoteOps\Packages` altında, kayıt başına sürümlü JSON dosyalarıyla saklanır. Yazmalar benzersiz geçici dosya ve atomik değiştirme ile yapılır; bozuk kayıt kullanıcıya gösterilir ve sessizce ezilmez. JSON içe ve dışa aktarma ekipte paket paylaşımını sağlar. İçe aktarmada şema doğrulanır, çakışmalar gösterilir ve üzerine yazma açık seçime bağlı olur. Kayıtlar yalnızca veri içerir; içe aktarma herhangi bir script çalıştırmaz.

Ortak, eşzamanlı yazılan UNC kataloğu ilk sürüme dahil değildir. Bu ihtiyaç oluşursa yazma yetkileri, çakışma ve revizyon yönetimi ayrıca tasarlanır.

## Downgrade davranışı

Her hedef bilgisayarda adımlar sırayla çalışır. Farklı hedeflerde mevcut worker altyapısıyla sınırlı paralellik kullanılabilir. Bir bilgisayardaki kaldırma ve kurulum eşzamanlı çalıştırılmaz.

| Mevcut durum | Downgrade kararı |
| --- | --- |
| Sürüm hedef sürümle eşit | Atlandı; paket çalıştırılmaz |
| Sürüm hedef sürümden yeni | Kaldır, kaldırıldığını doğrula, hedef sürümü kur, tam sürümü doğrula |
| Sürüm hedef sürümden eski | Atlandı; kurulum için Kur eylemi kullanılır |
| Uygulama yok | Atlandı; kurulum için Kur eylemi kullanılır |
| Kimlik belirsiz, sürüm okunamıyor veya karşılaştırılamıyor | Değişiklik yapılmadan hata |
| Bilgisayara erişilemiyor | Hata veya erişilemedi sonucu; paket çalıştırılmaz |

Kaldırma öncesinde kurulum ve kaldırma tanımları, PsExec varlığı, uygulama kimliği ve sürüm karşılaştırması doğrulanır. Seçili hesabın UNC dosyasını okuması ile hedef SYSTEM hesabının erişmesi farklı kontrollerdir; yerel erişim testi hedef erişimini garanti eden bir sonuç olarak sunulmaz. Hedefte kurulum kaynağı erişimi mevcut mekanizmalarla doğrulanamıyorsa kontrollü pilot aşamasında bu sınırlama açıkça test edilir.

Kaldırma başarılı değilse veya uygulama hâlâ bulunuyorsa kurulum adımı başlatılmaz. Kaldırma doğrulamasında mevcut worker'ın registry anahtarı davranışı incelenerek uygulamanın başka anahtarda kalması da değerlendirilir. Kurulum doğrulaması kaldırılmış uygulamanın eski seçilmiş nesnesini kullanmaz; hedef sürümün kimliğiyle yeniden tespit yapılır.

Downgrade başarı şartı karşılaştırma sonucunun sıfır olmasıdır. Mevcut sürüm kontrollü Install davranışındaki hedef sürüm veya daha yeni sürüm kabulü korunur; downgrade için eşitlik politikası ayrıca uygulanır. Worker tekrar denemeleri ve rapor sınıflandırması aynı doğrulama politikasını kullanır.

Kaldırma 3010 veya 1641 sonucu verirse zincir otomatik kuruluma geçmez; yeniden başlatma gerektiği veya başlatıldığı raporlanır. İlk sürüm otomatik yeniden başlatma ve otomatik devam yapmaz. Kurulum sonrası bu kodlar ayrıca gösterilir; tam sürüm doğrulanamıyorsa işlem başarılı downgrade olarak sayılmaz.

Kaldırma sonrasında kurulum başarısız olursa sonuç, uygulamanın kaldırıldığı fakat hedef sürümün kurulamadığı bilgisini açıkça içerir. Önceki sürüm için doğrulanmış kurtarma paketi bulunmadan otomatik rollback iddiası yapılmaz. Paket timeout veya sonuç belirsizliğinde otomatik tekrar tetikleme yapılmaz.

## Arayüz tasarımı

Ana sekmeler: Paketlerim, Paket Oluştur, Operasyon, Rapor. Açılışta Paketlerim gösterilir. Mevcut genel operasyonlar erişilebilir kalır. Profil seçimi üst alanda ortak bir hesap seçiciye taşınır; profil düzenleyicisi ayrı açılan panelde bulunur. Böylece paket çalıştırmak için Operasyon sekmesine geçmek gerekmez.

Paketlerim ekranında solda arama, kategori filtresi ve paket listesi; sağda seçilen paketin sürümü, kimliği, kaynakları ve desteklenen eylemleri bulunur. Alt bölüm hedef bilgisayarları ve çalıştırma özetini içerir. Tanımı eksik eylemler devre dışıdır ve nedenleri görünür. Eylemler Kur, Kaldır, Eski sürüme dön olarak Türkçe gösterilir.

Paket Oluştur ekranı Genel bilgiler, Kurulum, Kaldırma ve Doğrulama bölümlerinden oluşur. Koşullu alanlar yalnızca ilgili eylem için açılır. Kaldırma kimliğini kurulumdan kopyalamak kolaydır ancak ayrı düzenlenebilir. Hatalar alanın yanında gösterilir. Kaydet, Kopyasını oluştur ve Vazgeç eylemleri açıkça ayrılır. Mevcut manuel paket formundan Paket olarak kaydet kısayolu eklenir.

Tüm sekmelerde devam eden çalışmalar görünür bir ortak bölümden takip edilir. Hedef başına aşama, eski sürüm, hedef sürüm ve sonuç gösterilir. Bitiş metni yalnızca Tamamlandı olmaz; başarılı, atlanan ve hatalı hedef sayılarıyla birlikte gösterilir. Downgrade sırasında Kontrol ediliyor, Kaldırılıyor, Kaldırma doğrulanıyor, Kuruluyor ve Sürüm doğrulanıyor aşamaları görünür.

Görsel dil mevcut mavi ve açık zemin temelinde sadeleştirilir: ortak boşluklar, tutarlı kartlar, belirgin başlıklar ve tek ana eylem. İşlem durumları renk yanında metin ve simgeyle anlatılır. Segoe UI ve mevcut Windows ikonları kullanılır. Klavye odağı, sekme sırası ve okunabilir hata mesajları korunur. 1366x768 ekran ve yüzde 100 ile yüzde 125 ölçek için taşma ve erişilemeyen düğme kontrolü yapılır; mevcut 740 piksel minimum yükseklik bu hedefe göre gözden geçirilir.

## Çalışma motoru ve raporlar

Paket kaydı yönetimi, paket doğrulama ve downgrade yönlendirme kodu ayrı yardımcı dosyalarda tutulur. App dosyası ekranı ve kullanıcı akışını yönetir; Runner işi yürütür. Kayıt yolları ve katalog okuma sorumluluğu GUI tarafındadır. Runner'a katalog dosyasının yolu yerine doğrulanmış kayıt kopyası gönderilir; alternatif hesabın operatörün APPDATA dizinine erişmesine ihtiyaç duyulmaz.

Runner tüm girdileri tekrar doğrular. GUI doğrulaması, uzaktaki işlemler için güven sınırı olarak kullanılmaz. Mevcut Base64 istek ve komut satırı uzunluk sınırı korunur; daha büyük istekler açık mesajla reddedilir.

Yeni paket akışı ortak rapor sistemine bağlanır. Her çalışma için bir OperationID ve rapor klasörü vardır. Downgrade adımları hedef başına farklı alt kimliklerle kaydedilir; kaldırma ve kurulum logları birbirini ezmez. Sonuçta Paket adı, Kayıt kimliği, Revizyon, Eylem, Adım, Önceki sürüm, Hedef sürüm, Son sürüm, ExitCode, Yeniden başlatma gereksinimi ve hata nedeni bulunur.

Ledger hedef başına bir nihai sonuç kaydeder; her downgrade adımı ayrı bir operasyon gibi sayılmaz. Çalışma başlangıcında kullanılan paket tanımının kopyası rapor klasörüne yazılır. Rapor sekmesinde görünen paket adı, çalışmanın kullandığı kopyadan gelir.

İptal davranışı yeni paket akışında hedefler arasındaki ve downgrade adımları arasındaki sınırda kontrol edilen bir iptal isteğiyle başlar. Henüz başlamayan işler başlatılmaz; tamamlanan ve başlamayan hedefler kısmi raporda korunur. Aktif paket zorla kesilirse uzak sonucu bilinmeyen hedef Sonuç belirsiz olarak kaydedilir. Zorla durdurma ayrıca sunulur ve yerel süreç ağacının sonlandırılması uzak paket iptali olarak raporlanmaz. Var olan günlük toplamların bu yeni durumları yanlış başarı olarak saymaması test edilir.

Aynı uygulamanın aynı hedefte iki eşzamanlı dağıtımı, aynı yerel veri kökünü kullanan süreçler arasında kilitle engellenir. Kilit parola içermez; sahip süreç ve çalışma kimliğiyle izlenir, süreç bittiğinde temizlenir. Farklı operatör bilgisayarlarından gelen dağıtımlar için bu kilit ortak koordinasyon garantisi vermez.

## Uygulama sırası

| Aşama | Yapılacak iş | Tamamlama ölçütü |
| --- | --- | --- |
| 1 | Paket kayıt şeması, doğrulama ve depolama; çalışma sonucunun yeni alanları | Kayıt oluşturma, düzenleme, bozuk kayıt ve içe aktarma çakışmaları test edilir |
| 2 | Mevcut paket çalıştırmayı kayıt kopyasıyla çağırma; kimlik ve sürüm politikasını ayırma | Install ve Uninstall mevcut davranışlarıyla geçer; kayıt çalıştırması katalog yoluna bağlı değildir |
| 3 | Downgrade adımları, yeniden başlatma kararları ve hedef kilidi | Eşit, yeni, eski, yok, belirsiz, kaldırma hatası ve kurulum hatası senaryoları doğru sonuç verir |
| 4 | Paketlerim, Paket Oluştur ve ortak profil seçimi | Paket seç, hedef gir, özetle, çalıştır akışı tamamlanır; manuel formdan kayıt yapılabilir |
| 5 | Ortak ilerleme alanı, kısmi rapor ve paket adıyla raporlar | Aktif iş sekme değişince görünür kalır; iptal ve adım sonuçları korunur |
| 6 | Görsel düzenleme, mevcut testler, yeni testler ve kılavuz | PS 5.1 regresyonları geçer; ekran ve ölçek kontrolleri tamamlanır |
| 7 | Kontrollü şirket test bilgisayarında pilot | Gerçek UNC, seçili hesap, SYSTEM erişimi ve üç dağıtım eylemi doğrulanır |

Görsel tasarım aşama 4 sonunda ekran üzerinden birlikte gözden geçirilir; tüm kod bittikten sonraya bırakılmaz. Uygulama koduna başlamadan bu kapsam ve kararlar gözden geçirilir, ardından dosya ve test görevlerini içeren ayrıntılı uygulama planı hazırlanır.

## Kabul senaryoları

- Uygulamayı kapatıp açınca paket tanımları kalır; düzenlenen kayıt sonraki çalışmalarda kullanılır.
- Paket kaydetme, içe aktarma veya seçme uzak bilgisayarda hiçbir işlem yapmaz.
- Tanım doğrulaması eksik UNC, geçersiz dosya adı, eksik kimlik ve downgrade için eksik sürümü alan bazında gösterir.
- Bir tanımdan Install, Uninstall ve Downgrade yalnızca yapılandırıldıkları durumda başlatılır.
- Farklı kaldırma ve kurulum ProductID'leri doğru aşamada kullanılır.
- Downgrade ön kontrol hatasında hiçbir kaldırma yapılmaz; kaldırma doğrulanmadan kurulum başlamaz.
- Downgrade son kontrolünde hedef sürümden yeni sürüm başarı sayılmaz.
- 3010, 1641, timeout ve erişim hataları doğru aşama ve yeniden başlatma bilgisiyle raporlanır.
- Çoklu hedefte bir hedefin hatası diğer hedeflerin sonuçlarını bozmaz; ledger hedef başına bir kayıt tutar.
- Çalışma sırasında katalog düzenlemek aktif paketi değiştirmez.
- Aynı yerel koordinatörde aynı uygulama ve bilgisayar için çakışan işlem engellenir.
- İptal edilen çalışma tamamlanan hedefleri kaybetmez; belirsiz hedefleri başarılı saymaz.
- Yeni sekmeler mevcut katalog, XAML kontrol eşleştirme, paket, paralellik, profil ve rapor testleriyle birlikte doğrulanır. Sekme indeksi yerine sekme kimliği kullanılır.
- En az 1366x768 ekranda ve yüzde 100 ile yüzde 125 ölçekte ana eylemler erişilebilir; kaydırma gerektiğinde düzgün çalışır.

## İlk sürüm sonrası

Genel amaçlı Operasyon Oluştur, ortak UNC kataloğu, onay akışı, otomatik yeniden başlatma sonrası devam ve kurtarma paketiyle otomatik rollback ayrı geliştirmelerdir. Mevcut tüm dosya ve servis modüllerinin yeniden yazımı bu paket yönetimi çalışmasının ön koşulu değildir; paket alanındaki arayüzler hedefli biçimde düzenlenir.

## Gözden geçirilecek varsayımlar

İlk paket kataloğu kişiseldir; ekip paylaşımı JSON dışa ve içe aktarmayla sağlanır. Paket Oluştur mevcut dağıtım dosyasına kayıt açar. Downgrade uygulama yokken kurulum yapmaz, mevcut sürüm daha eskiyse yükseltme yapmaz. Genel tarif motoru ilk teslimata dahil değildir. Bu seçimler kapsam incelemesinde değiştirilebilir.
