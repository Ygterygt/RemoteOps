# RemoteOps kullanım kılavuzu

14 Ekim 2026 · YD_RemoteOps.App_v11 · Operatör rehberi

Bu kılavuz güncel dört sekmeli arayüzü ve şirket pilotunda izlenecek yolu açıklar. Ekranlar gerçek WPF kontrollerinden örnek verilerle üretilmiştir; şirket ağında yapılmış test sonucu değildir. Ayrıntılı yapı [teknik el kitabında](TEKNIK_EL_KITABI.md), süreç akışı [çalışma mantığında](CALISMA_MANTIGI.md) bulunur.

## 1. Şirket bilgisayarına taşıma

1. Klasörün tamamını kopyalayın; Modules ve RemoteOps.App birlikte kalmalıdır.
2. Kökteki YD_RemoteOps.App.bat dosyasını açın. Windows PowerShell 5.1, WPF ve FullLanguage çalışma ortamı gerekir.
3. Profili şirket bilgisayarında tanımlayın. İlk pilotta paralel bilgisayar sayısını 1 seçin.
4. Önce tek test hedefinde uygulama envanteri alın; gerçek kimlik/sürüm bilgisini kaydedin.
5. [Pilot kontrol tablosunu](PAKET_YONETIMI_PILOT_KONTROLU.md) doldurup dağıtım senaryolarına geçin.

Kişisel profil dosyasını başka bilgisayara taşımayın; parolalar Windows kullanıcı hesabına bağlı DPAPI ile korunur. Paket tanımları JSON dışa/içe aktarımıyla taşınabilir. Veri kökü kaynak klasör adı değişse de C:\Temp\YD_RemoteOps.App olarak kalır. Şirket ağında gerekli uzak yönetim erişimleri teknik el kitabında açıklanır.

## 2. Ekran düzeni ve hesap seçimi

Üst hesap ve paralellik seçimi bütün sekmeler için ortaktır. Paketlerim varsayılan sekmedir. Paket Oluştur kayıt düzenler, Operasyon diğer bakım işlerini açar, Rapor günlük özeti gösterir. Devam eden işler ve sonuçlar alt paneli bütün sekmelerden izlenebilir; yeni işte açılır. Teknik aktivite ayrıntılı çıktıdır.

![Paketlerim ekranı](paket-ui-preview/library.png)

Şekil 1. Paketlerim: solda arama/kayıt listesi, sağda paket ayrıntıları ve hedefler, sabit alt bölümde Kur/Kaldır/Eski sürüme dön. TEST hesabı ve örnek sunucu/bilgisayarlar eğitim verisidir.

Main mevcut Windows oturum token'ıyla çalışır; kaydındaki parola oturumu değiştirmez. Başka hesap için Profiller düğmesiyle ayrı profil oluşturup üst listeden seçin. Alternatif hesap uygulama/modül/PsExec dosyalarını okuyabilmeli, veri alanına yazabilmeli ve hedefleri yönetebilmelidir.

![Profil düzenleme paneli](profiller.png)

Şekil 1a. Profiller paneli. Görselde parola ve gerçek şirket hesabı bulunmaz; başka bilgisayarda profiller yeniden tanımlanır.

Paket hedefte SYSTEM olarak çalışır. Yönetici hesabının UNC klasörünü açabilmesi SYSTEM erişimini kanıtlamaz. Kaydedilmiş dağıtım kaynak dosyasını SYSTEM altında salt okunur probe ile sınar. Scriptin çağırdığı ek dosyaların erişimi ayrıca pilotta doğrulanmalıdır.

## 3. Paket Oluştur

Bu ekran mevcut .bat/.cmd/.ps1/.vbs scriptini tanımlar; yeni MSI, EXE veya script üretmez. Kaydetme hedefte işlem başlatmaz.

![Paket editörü](paket-editor-genel.png)

Şekil 2. Paket genel bilgileri. Uzun içerik kaydırılır; kaydetme alanı altta kalır.

1. Ad, kategori, açıklama, hedef sürüm ve uygulama ailesi anahtarını girin. Aynı uygulamanın tüm sürümlerinde aynı aile anahtarını kullanın.
2. Kurulum eylemini açın; UNC klasörünü ve ayrı dosya adını girin. Örnek: \\paket-sunucusu\Dagitim\OrnekApp\2.0 ve install.cmd.
3. Arama türü, uygulama kimliği ve kontrol modunu seçin. Gerekirse tam RegistryKey ile eşleşmeyi daraltın.
4. Kaldırma gerekiyorsa ayrı eylemi açıp kaldırma kaynağı/kimliğini girin. Sürümler arasında ProductID değişebilir.
5. Eski sürüme dönüş tanımı ekle kutusunu açın. Ayrı alana eski hedef sürümünü, eski sürüm UNC klasörünü/scriptini ve uygulama kimliğini girin. Kaldırma tanımı da etkin olmalıdır. Normal kurulum paketi bu eylemde kullanılmaz.
6. Gerekiyorsa log toplamayı açın. Kaydet'e basıp hata açıklamalarını giderin.

![Bağımsız kurulum ve kaldırma tanımları](paket-editor-eylemler.png)

Şekil 2a. Editör aşağı kaydırıldığında iki eylem görünür. NEW-ID ve OLD-ID örnek kimliklerdir; gerçek değerler şirket uygulama envanterinden alınmalıdır.

![Ayrı eski sürüm paketi tanımı](paket-editor-eski-surum.png)

Şekil 2c. Eski sürüme dönüş için ayrı UNC/script, eski hedef sürüm ve kimlik. Örnekte normal kurulum 2.0, eski hedef 1.0'dır. Bu eylem önce Kaldırma tanımını kullanır, yokluğu doğrular ve yalnızca bu alandaki eski paketi kurar. Normal Kur ve Kaldır birbirinden bağımsız seçilir; tanımların birlikte işaretlenmesi otomatik zincir başlatmaz.


| Alan/seçim | Anlamı |
| --- | --- |
| UNC klasör / Dosya | Paylaşım klasörü ve yalnızca .bat/.cmd/.ps1/.vbs dosya adı. |
| DisplayName exact | Uninstall kaydındaki görünen adın tam eşleşmesi. |
| DisplayName contains | Ad içinde arama; çoklu eşleşme ihtimalini kontrol edin. |
| ProductID | Uninstall kayıt kimliği; gerçek değeri ApplicationInventory ile doğrulayın. |
| RegistryKey | İsteğe bağlı tam anahtar sınırı; yanlış anahtar tespiti engeller. |
| Version controlled | Varlık ve sürüm kontrolü. Normal Kur hedef veya üst sürümü kabul eder. |
| Presence only | Varlık/yokluk kontrolü; sürüm eşitliği aranmaz. |
| Trigger without checks | Uygulama doğrulaması olmadan tetikleme; kuruldu/kaldırıldı kanıtı değildir. |

Script sessiz çalışmalı ve gerçek yükleyici exit code'unu iletmelidir. EXE/MSI uygun script içinden çağrılır. SYSTEM yürütmesi kullanıcıya soru soran paketler için uygun değildir. Scriptin kendi davranışı da şirket pilotunda kontrol edilir.

## 4. Paketlerim: yönetme ve paylaşma

Arama/kategori ile paketi bulun. Düzenle aynı kaydı günceller; Kopyala yeni GUID'li kayıt üretir, aile anahtarını korur. Yeni sürüm tanımı için kopyalama kullanılabilir. Sil katalog kaydını siler; hedefte yazılım veya UNC dosyası silmez.

Dışa aktar tanımları JSON ile paylaşır. İçe aktar doğrulama ve çakışma önizlemesi yapar; Atla/Kopyala/Değiştir politikası seçilir. Parola, hedef listesi ve onay aktarılmaz. Alınan tanımın kaynak ve kimliklerini şirket ortamında kontrol edin. Katalog kişiseldir: %APPDATA%\MDRemoteOps\Packages. Revizyon çakışmasında en güncel kaydı yeniden açın.

## 5. Kur veya Kaldır

1. Doğru paket/sürümü ve üst çalışma hesabını seçin.
2. Hedef alanına bilgisayar adlarını girin; satır, boşluk, virgül veya noktalı virgül ayırıcı kullanabilirsiniz. Tekrarlar temizlenir.
3. Kur/Kaldır'a basın; özette hesap, hedefler, eylem, kaynak ve kimlikleri kontrol edin.
4. İstenen onayı tam büyük harfle TRIGGER yazıp çalıştırın. Özet açıkken hesap değiştiyse özeti yeniden açın.
5. Aşamaları ortak izleme panelinden takip edin; sonuç raporunu inceleyin.

![Çalıştırma özeti ve onay](paket-onay.png)

Şekil 2b. Downgrade için örnek çalıştırma özeti; hesap, hedefler, iki kaynak ve onay birlikte gösterilir. Görselde iş başlatılmamıştır.

Çalışma bağımsız tanım snapshot'ını kullanır; sonraki katalog düzenlemesi işi değiştirmez. Kontrollü Kur hedef veya daha yeni sürüm kuruluysa atlayabilir. Kontrollü Kaldır uygulama yoksa atlar; çalıştırdıysa yokluğu doğrular. Kontrolsüz tetikleme uygulama varlığını/sürümünü ayrıca doğrulamaz.

## 6. Eski sürüme dön

Paket ve hedefleri seçip Eski sürüme dön eylemini açın; özette DOWNGRADE onayını kullanın. Akış: mevcut kimlik/sürüm; kaldırma ve ayrı eski sürüm kaynaklarına erişim; kaldırma; yokluk doğrulaması; eski sürüm paketini kurma; eski hedef sürümün tam doğrulaması.

| Durum | Davranış |
| --- | --- |
| Daha yeni sürüm ve doğru kaldırma kimliği | İki kaynak doğrulandıktan sonra downgrade. |
| Eşit, daha eski veya uygulama yok | Skipped; gerekiyorsa Kur kullanın. |
| Kaynak erişilemiyor, kimlik belirsiz/yanlış | Değişiklikten önce durur. |
| Kaldırma hata veya uygulama hâlâ var | Kurulum başlamaz. |
| Kaldırma 3010/1641 | RebootRequired; otomatik kurulum/reboot yok. |
| Kaldırma bitti, kurulum başarısız | Kaldırılmış durum adım kaydında görünür; otomatik geri kurulum yok. |
| Son sürüm hedefe eşit değil | Başarı sayılmaz; detay incelenir. |

Downgrade transaction/otomatik rollback değildir. Pilot öncesinde kurtarma paketini ve sorumlusunu belirleyin. Sayısal karşılaştırılamayan sürümlerde zorla downgrade yapılmaz.

## 7. Durdurma ve belirsiz sonuç

Tamamlanan sayısı girişimi biten hedeflerdir; hepsi başarılı olmayabilir. Aşama ve sonuçla birlikte okuyun. Kaydedilmiş dağıtımda Durdur yeni hedef/adımı engeller; aktif paket adımını bekler. Zorla durdur yerel süreç ağacını kapatır. Uzak paket devam edebilir; sonucu doğrulanamayan hedef Indeterminate olur. Checkpoint verilerinden kısmi rapor hazırlanır.

Diğer operasyonlarda Durdur yerel süreç sonlandırmadır; aynı kısmi rapor davranışı her işlemde geçerli değildir. Pencereyi çalışırken kapatmak takibi keser; tam uygulama çökmesinden sonra otomatik devam yoktur. Timeout/force stop/Indeterminate sonrasında hedefte yükleyici, varlık/sürüm ve logları kontrol etmeden tekrar dağıtım yapmayın.

## 8. Diğer operasyonlar

Operasyon sekmesi seçilen iş için alanları gösterir. Manuel Install or uninstall package formu kayıt oluşturmadan kur/kaldır çalıştırır; Bu tanımı paket olarak kaydet kısayolu vardır. Manuel form downgrade sağlamaz. Kısayol Paketi Oluştur editörünü doldurur; doğrudan kaydetmez. Paket adını değiştirebilir ve kategori girebilirsiniz. Paketi kaydet düğmesiyle kişisel kataloğa eklenir; hedefler ve onay taşınmaz.

![Operasyon sekmesi](operasyon.png)

Şekil 3. Güncel Operasyon ekranı; örnek verilerle, uzak işlem başlatılmadan.

![Operasyon hedeflerini ortak tabloda izleme](operasyon-izleme.png)

Şekil 3a. Manuel paket ve diğer operasyonlarda bilgisayar, paket/işlem etiketi, bekleme/çalışma/bitiş ve sonuç ortak tabloda görünür. Görsel örnek ilerleme verisidir; gerçek hedef çalıştırılmamıştır. Eşzamanlı işler birbirinin satırlarını ezmez.

Devam eden işler ve sonuçlar panelinde yeni iş başlayınca yalnızca son çalıştırma seçilir. Saat, paket/eylem, hedef sayısı ve oturum sıra numarasıyla önceki çalıştırmaları seçebilirsiniz. Seçim geçmiş sonuçları silmez; arka plandaki güncellemeler seçimi değiştirmez. Tüm çalışmalar seçildiğinde bilgisayar satırları çalıştırma başlıkları altında gruplanır; aynı bilgisayar farklı işlerde ayrı satırdır. Seçili çalıştırmanın hedef/durum sayıları tabloda gösterilir. HTML raporunu aç düğmesi yalnızca seçili işin raporu oluştuğunda etkinleşir; toplu görünümde kapalıdır. Üstteki devam eden iş sayısı bütün aktif işleri gösterir.

Bu seçim geçmişi açık uygulama oturumuna aittir; yeniden açılışta boş başlar. Kalıcı raporlar Rapor sekmesinde ve log klasörlerinde korunur. Durdur/Zorla durdur düğmeleri mevcut davranışla bütün aktif işleri etkiler; çalışma seçimi durdurma kapsamını değiştirmez.


| Grup | İşlev / kullanım sınırı |
| --- | --- |
| Applications | Varlık ve uygulama envanteri, manuel paket; gerçek kimliği buradan doğrulayın. |
| Files | Çek/gönder/karşılaştır/yedekle-sil/taşı/değiştir. Restore silme yedeği, Rollback dosya manifesti kullanır. |
| Inventory | Uç nokta ve ayrıntılı sağlık. HealthCheck tüm liste için tek Health.html üretir. |
| Registry | HKLM string okuma/değiştirme/silme/geri alma; genel türler desteklenmez. |
| Services | Liste, Start/Stop/Restart, başlangıç türü/geri alma; tam servis adı kullanılır. |
| Tasks | Liste/Run/Enable/Disable/XML yedekli silme; aynı ad varsa görev yolu gerekir. |
| Processes | Ad/PID sorgu ve tam ad/PID kill; kritik süreçler korunur, kill geri alınmaz. |

Değişiklikte ekrandaki onayı tam yazın: DELETE, EDIT, RESTORE, ROLLBACK, KILL veya eylem adı START/STOP/RESTART/RUN/ENABLE/DISABLE/MOVE/REPLACE. Görev silmede parola tabanlı görevler korunur; XML parola geri getiremez. Geri almada yedek/manifest ve hedef kapsamını kontrol edin.

## 9. Rapor ve dosyalar

Rapor sekmesinde günü seçin; durum, kategori, saat ve bilgisayar dağılımını inceleyin. HTML olarak aç günlük raporu verir. Kategori alanını aşağı kaydırınca paket ve Kur/Kaldır/Eski sürüme dön eylemiyle hedef sayıları görünür. Dikkat sayısı hata, erişilememe, belirsizlik ve reboot gereksinimini kapsar; iptaller ayrıdır. Aynı sayımlar günlük HTML'e de eklenir.

![Rapor sekmesi](rapor.png)

Şekil 4. Güncel günlük rapor; gösterilen iki hedef ve sonuçlar özel geçici alana yazılmış eğitim verisidir.

![Paket ve eylem kırılımı](rapor-paketler.png)

Şekil 4a. Kategori alanı aşağı kaydırıldığında paket/eylem bazında sonuçlar. Bir downgrade hedefi adım sayısı kadar çoğaltılmaz.

| Sonuç | Okuma biçimi |
| --- | --- |
| Success | Tanımlı başarı koşulu geçti; kontrolsüz mod uygulama durumunu kanıtlamaz. |
| Skipped | Bilinçli atlama; nedenini okuyun. |
| Error / Unreachable | Bilinen işlem/erişim sorunu; teknik logu kontrol edin. |
| Cancelled | İptal nedeniyle tamamlanmayan/başlamayan hedef. |
| Indeterminate | Son durum bilinmiyor; hedefte manuel doğrulama. |
| RebootRequired | Reboot gereksinimi; şirket prosedürü ve tekrar tespit. |

Paket sonuç HTML ana tablosu hedef başına tek nihai özet gösterir. ExitCode ve log hedefi son yürütme adımından tamamlanır; ExecutionStep hangi adıma ait olduğunu belirtir. Adım ayrıntıları açılarak kaldırma/kurulum/doğrulama kayıtları görülebilir. CSV ve checkpoint özgün adım satırlarını korur. Nihai Result oluşmadan hata veren hedefler de özetten düşmez. Günlük sayım terminal hedefi bir kez sayar.

Çalışma çıktıları C:\Temp\YD_RemoteOps.App\Logs\Operations\<Operasyon>\<OperationID> altındadır: Results.csv/html, Activity.csv/html, RemoteOps.log ve kaydedilmiş dağıtımda PackageDefinition.json. Workers paralel süreç çıktıları, Detail ara modül raporlarıdır. Paket logları PulledLogs\<PC>\<AdımID_Operasyon> altındadır. Pilot tablosuna OperationID ve rapor yolunu yazın.

## 10. Ayarlar, log ve ekran ölçeği

![Ayarlar](ayarlar.png)

Şekil 5. Paket log temizleme ayarı; toplama ve hedefte temizleme ayrı eylemlerdir.

Paket tanımındaki log toplama yerel PulledLogs alanına dosya çeker. Ayarlardaki temizleme ancak log toplama açıkken ve geçerli kullanıcı adıyla etkinleşir; hedefte kullanıcı adıyla eşleşen loglar için korumalı akış uygulanır. İlk pilotta temizlemeyi kapalı tutmak incelemeyi kolaylaştırır. Activity temizle sadece ekran metnini temizler. Log klasörünü aç yerel logları açar. Saklama/disk temizliği ayrıca planlanır; yedek ve manifestleri ayırmayın.

Toplama C:\Windows\Temp altında son 10 dakikada oluşturulmuş/değişmiş .log/.txt dosyalarını içerir; başka işlemlerin logları da gelebilir. Temizleme sadece başarıyla çekilmiş, hash'i değişmemiş, doğrudan Temp içindeki uygun kullanıcı adlı dosyaları değerlendirir; hata/timeout paketinde temizleme yoktur. DeleteBackups içindeki silme yedekleri modül başlatılınca 7 günden eski LastWriteTime için temizlenebilir; uzun süreli kurtarma kopyası ayrıca tutulmalıdır.

![Yüzde 125 görünüm](paket-ui-preview/library125.png)

Şekil 6. Yüzde 125 kısa ekran testi; ayrıntı kaydırılır, alt eylemler görünür kalır. Şirket ekranında 1366x768 ve kullanılan ölçekte tekrar kontrol edin.

Pilot sırası: tek hedef salt okunur tespit; kayıt/kopya/export/import; Kur; Kaldır; yeni sürümde downgrade; erişim/kimlik hataları; reboot kodları; Durdur/Zorla durdur; küçük çok hedefli çalışma. Her senaryoda ilk/son sürüm, exit code, OperationID ve rapor yolu kaydedilir. Yerel doğrulama durumu [inceleme raporunda](INCELEME_RAPORU.md) bulunur.

## 13. Güvenilirlik denetimi sonrası notlar

Main profilini silmek başka bir hesabı mevcut Windows oturumu hesabına dönüştürmez; kalan kayıt kendi credential profili olarak kalır. Bozuk JSON alanları içe aktarımda reddedilir. Kategori değiştirilince filtre geçersiz kalırsa Tüm kategoriler görünümü doğru yenilenir. Beklenmedik biten paket işinde sonuçlar çalışıyor görünmez; belirsiz/hata durumunu ve kısmi raporu kontrol edin. Registry/servis değişikliklerinde geri alma dosyası yazılamıyorsa işlem yapılmaz. Test raporu INCELEME_RAPORU.md/PDF içindedir.


## 14. Erişim ön kontrolü ve toplanan loglara erişim

Bütün operasyonlarda her hedefe işlem yapılmadan önce mevcut çalışma hesabıyla gerekli bağlantı kontrol edilir. Dosya işlemleri SMB admin$ paylaşımına salt okunur erişimi; registry işlemleri root\default, servis/görev/süreç işlemleri root\cimv2 yönetim bağlantısını sınar. Kayıtlı paketlerde kontrollü işlemler SMB ve yönetim bağlantısını, kontrolsüz script tetikleme yalnızca SMB bağlantısını gerektirir. Ping ön koşul değildir. Bağlantı kurulamayan hedefte işlem çalıştırılmaz; sarı Atlandı - Erişilemedi sonucu üretilir ve sonraki hedefe geçilir. Yetki reddi ve tanınmayan bağlantı hataları kırmızı hata kalır. Ön kontrolün başarısı sonraki işlemin başarılı olacağını garanti etmez; kaynak, PsExec/SYSTEM ve uygulama kontrolleri kendi akışlarında devam eder.

Log toplama açık ve paket tetiklenmişse, yeni paket çalıştırmalarının logları PulledLogs\<ÇalıştırmaID>\<Bilgisayar>\<AdımID_Operasyon> altında tutulur. Downgrade kaldırma/kurma adımları aynı çalıştırma ve bilgisayar klasöründe ayrı alt klasörlerdir. Diğer dosya operasyonları ve geçmiş log klasörleri mevcut konumlarında kalır.

Devam eden işler ve sonuçlar alanındaki Toplanan loglar düğmesi seçili çalıştırmanın klasörünü açar. Bilgisayar satırındaki Logları aç yalnızca ilgili çalıştırma/bilgisayar klasörüne gider. Dosya yoksa düğme pasiftir; Log durumu toplanmadı, log bulunamadı veya toplama başarısız bilgisini gösterir. Kısmi dosyalar varsa mevcut dosyalar açılabilir ve toplama hatası ayrıca gösterilir. Tüm çalışmalar seçiliyken üst düğme kapalıdır; bilgisayar satırlarındaki kısayollar kullanılabilir. Yeni kısayollar yeni çalıştırma düzeni içindir; önceki sürümdeki loglara Log klasörü/dosya gezgini ile erişilir.


## 15. Eski paket kayıtlarının yeni tanıma geçişi

Yeni kayıt biçimi RemoteOps.Package/2, dışa aktarım biçimi RemoteOps.PackageExport/2'dir. Eski /1 kayıtları ve dışa aktarımları okunabilir. Önceden downgrade etkinse eski Install ve TargetVersion bilgileri ayrı Downgrade ve DowngradeVersion alanlarına kopyalanır; böylece önceki çalıştırma anlamı korunur. Okumak dosyayı değiştirmez; yeniden kaydetmek revizyon artırarak /2 biçimini yazar. Taşınan yolları kontrol edip normal Kurulum alanını güncel sürüme, Eski sürüm alanını gerçekten dönülecek pakete göre düzenleyin. Yeni /2 dosyaları eski uygulama kopyasıyla kullanılmamalıdır; uygulama klasörünü birlikte güncelleyin. Yeni tanımda downgrade için normal Kurulum zorunlu değildir; Kaldırma ve Eski sürüm tanımları zorunludur.


## 16. Operasyon giriş örnekleri ve çekilen dosyalar

Dosya, registry, görev, servis ve süreç alanlarının altında kısa örnekler bulunur. Bunlar açıklamadır; gerçek girdi ve onay kutularına otomatik değer yazılmaz. Servis için görünen ad yerine Name, süreç sonlandırma için önce sorgulayarak doğrulanan PID/tam ad, registry için HKLM alt anahtarı ile ayrı değer adı girilir. Görev silmede Task folder ayrı alandır; görev çalıştırmada aynı ad belirsizse işlem reddedilir.

![Dosya çekme giriş örneği](ornek-dosya.png)

Yeni dosya çekimleri PulledFiles\<ÇalıştırmaID>\<Bilgisayar> altında saklanır. Üstteki Çekilen dosyalar düğmesi seçili çalıştırmanın klasörüne gider. Satırdaki Çekileni göster tek dosyayı Explorer içinde seçer, birden fazla dosyada ilgili istemci klasörünü açar. Dosya yoksa düğme pasiftir; Tüm çalışmalar görünümünde üst düğme kapalı, satır kısayolları kullanılabilir. Script/exe dosyaları kısayol üzerinden otomatik çalıştırılmaz. Eski sürüm çekimlerinin klasör düzeni yerinde kalır.

![Registry alan örnekleri](ornek-registry.png)

v10 yerel canlı test ayrıntıları [canlı test raporunda](CANLI_TEST_RAPORU.md) bulunur. Canlı test scripti normal otomatik test turuna dahil değildir; yalnızca açık -RunLive ile çalışır, yönetici yetkisi ister ve kendi geçici kaynaklarıyla sınırlıdır.


## 17. v11 erişilebilirlik ve kişisel script paketleri

Erişilemeyen hedefler Devam eden işler ve sonuçlar tablosunda sarı gösterilir; Rapor ve HTML özetlerinde Atlanan / Yok / Erişilemedi grubuna eklenir. CSV ve günlük kayıtlar teknik Unreachable sonucunu korur. Yetki reddi, kaynak hatası, başarısız script çıkışı ve doğrulama hatası kırmızı kalır; belirsiz sonuç/yeniden başlatma durumları ayrıca Dikkat olarak izlenir. Hiçbir hedef sonuç listesinden sessizce çıkarılmaz.

Kişisel script için paket adı ve kategori (örneğin Kişisel scriptler) girin, Kurulum işlemini etkinleştirin ve Kontrolsüz tetikle seçin. Hedef sürüm ile uygulama kimliğini boş bırakabilirsiniz. UNC klasörünü ve .bat/.cmd/.ps1/.vbs dosya adını girip kaydedin; Paketlerim > Kur ile çağırın. Bu mod uygulamanın kurulu olduğunu veya sürümünü doğrulamaz; script sonucunu değerlendirir. Script mevcut uzak çalışma mekanizmasında SYSTEM hesabıyla yürütülür; kullanıcı masaüstü etkileşimi beklememelidir.

![v11 erişilemeyen hedef sarı örneği](paket-ui-preview/operasyon-erisilemedi.png)

![v11 HTML sonuç dağılımı: erişilemeyen tek hedef sarı, hata sıfır](paket-ui-preview/sonuc-dagilimi-v11.png)

Her tamamlanan değişiklik tesliminde dağıtım sürümü bir artırılır, VERSION.json ve belgeler güncellenir ve yeni sürüm ZIP olarak Drive'a eklenir. Önceki sürüm korunur.
