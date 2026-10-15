# v18 — Operasyon reçeteleri teslim incelemesi

15 Ekim 2026 · YD_RemoteOps.App_v18 · Önceki sürüm v17

## Sonuç

Dokuzuncu sekmede 1–20 adımlı kişisel reçete kaydetme/kopyalama, sıralama, paket snapshot ve RECETE onaylı önizleme eklendi. İzin verilen servis/dosya/registry/paket adımları mevcut Runner ile hedef başına sırayla yürür. İlk durdurucu sonuçta o hedefin kalan adımları çalışmaz. Geçmişte tek üst reçete ve hedef başına tek terminal sonuç bulunur; reçete adı ve özgün adım/exit-code ayrıntıları korunur.

## Gerçek doğrulama kapsamı

- Başlangıç67/67 test dosyası geçti.
- Son tam tur72/72 test dosyası geçti; sayılar test dosyasıdır, assertion veya canlı hedef sayısı değildir. [Test sonuçları](V18_TEST_RESULTS.csv).
- Son reçete adı/geçmiş ve küçük ekran düzeni için dokuz etkilenen dosya ayrıca çalıştırıldı. [Ek doğrulama](V18_AFFECTED_RERUNS.csv).
- Windows PowerShell5.1 parser:108 dosya,0 hata. [Kayıt](V18_PARSE_RESULTS.csv).
- Şema/revizyon/katalog/kimlik, yasak alanlar ve paket içindeki gizli alan reddi, değişmez snapshot ve Unicode/büyük istek sınırı doğrulandı.
- Durum eşleme testleri: salt okunur NotFound ile mutasyon hatası ayrımı, karma satırda tek hata, karşılaştırma farkı, atlanan dosya, doğrulanmış paket atlaması ve reboot önceliği.
- Gerçek üst Runner ve dört child Windows PowerShell süreci yerel kopyada çalıştırıldı; bütün uzak CIM/SMB/PsExec sınırları sahtedir. PC/adım sırası, exact OperationID ve tek ledger kanıtlandı. [Günlük](v18-test-logs/RemoteOps.RecipeExecution.Tests.ps1.txt).
- Gerçek WPF: dokuzuncu sekme/editör, kaydedilmiş önizleme, iptal, değişmiş hesap/kayıtsız düzenleme, yeni RECETE onayı ve yalnız bir kez dispatch. Küçük ekran için bütün editör kaydırılabilir. Normal/%125 görseller gözle incelendi.
- Tek üst geçmiş, özgün50010, HTML escape, aktif kesinti kimliği, kalan NotRun ve idempotent kısmi rapor doğrulandı.
- Beş PDF yeniden üretildi; sayfalar render edilerek gözle kontrol edildi.
- Gerçek şirket hedefinde canlı işlem yapılmadı. Bu yerel testler şirket kabulü değildir.

## Bağımsız inceleme ve düzeltmeler

| Bulgu | Düzeltme / kanıt |
| --- | --- |
| Timeout sonrası alt süreç takibi kayboluyordu | Süreç takipte kalır; bekleme eşiği sonrası bütün yeni işler engellenir. Sahte süreç/saat regresyonu RED→GREEN |
| Kesilen aktif adım raporda kimliğini kaybediyordu | StepId,StepIndex,StepOperationID ve Operation taşıyan Indeterminate satırı; RED→GREEN |
| Yeniden açılışta checkpoint onarımı bağlı değildi | Açılışta PID+başlangıç zamanı kontrolü; kesik kayıt raporlanır, çalışan Runner atlanır ve onarım tekrarlanmaz |

İlave düzeltmeler: küçük pencerede dış kaydırma ve geçmiş listesinde reçete adı regresyonlarla doğrulandı. Paket atlama gerekçeleri serbest metinden tahmin edilmez; dört açık DecisionCode kullanılır. Mevcut paket/tek operasyon davranışları korunur.

## Sınırlar

Dosya gönderme üzerine yazabilir; otomatik yedek veya reçete genelinde rollback yoktur. Hatalı adım sonrası önceki değişiklikler kalabilir. Durdur, aktif uzak mutasyonun kesin durması anlamına gelmez. 7200 saniye bekleme eşiğinde yeni işler durur; aktif yerel süreç bitene veya açık force-stop yapılana kadar takip sürer. Bu nedenle bekleme7200 saniyeyi aşabilir. Belirsiz uzak sonuç başarı diye gösterilmez.

Hedefler ve adımlar sıralıdır; küresel operatörler arası hedef kilidi yoktur. Serbest kod, iç içe tarif, koşullu dal/değişken, import/export/ekip kataloğu, otomatik retry/resume/reboot yoktur. Üst ve alt istekler22000 Base64 karakter sınırına tabidir; fazla veri kesilerek çalıştırılmaz. Yerel önizleme hedef durumu garantisi değildir.

## Dağıtım

v17 klasörü/ZIP'i korunur. Runtime C:\Temp\YD_RemoteOps.App, kişisel veri %APPDATA%\MDRemoteOps olarak kalır. v18 ZIP son doğrulamadan sonra oluşturulur; bütün girdiler SHA-256/CRC ile kaynakla karşılaştırılır. [Dosya doğrulaması](V18_VALIDATION.json). Drive yüklemesi yapılmaz.

[Ekran](screenshots-v18/operasyon-receteleri.png) · [%125 editör](screenshots-v18/operasyon-receteleri-125.png) · [Kaydet/çalıştır alanı](screenshots-v18/recete-calistirma-125.png) · [Önizleme](screenshots-v18/recete-onizleme.png)
