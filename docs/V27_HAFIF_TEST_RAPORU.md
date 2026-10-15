# v26 reçete ve koşul akışı - hafif kabul testi

Sonuç: **17/17 operasyon senaryosu geçti.** Ek olarak 12/12 güvenli yerel regresyon dosyası ve 5/5 model sınırı negatif kontrolü geçti. Bağımsız inceleme 16 çalışma kaydını doğruladı.

Uygulama kodunun 36 dosyası v26 ile birebir aynıdır. v27 yalnızca test araçları ve doğrulama teslimidir. Sanal makine kullanılmadı. Kabul koşusu 148.88 saniye sürdü; örneklenen toplam çalışma belleği 699.8 MiB oldu.

## Nasıl test edildi

Gerçek WPF denetimleriyle Adım ekle, işlem ve koşul alanları, otomatik ad, kaydetme, katalogdan yeniden açma, önizleme ve RECETE onayı kullanıldı. Gerçek Start-RemoteOpsRequest istek oluşturdu; gerçek koordinatör ve ayrı PowerShell çocuk süreçleri çalıştı. Gerçek servis operasyon modülü, koşul karşılaştırma/karar kodu ve raporlama kullanıldı. Yalnızca geçici kopyada uzak erişim sınırları ve çocuk süreç başlatma bağları yerel modele yönlendirildi. Üretim kodu değiştirilmedi.

## Senaryolar

| No | Senaryo | Sonuç |
|---|---|---|
| 1 | Koşul, servis başlatma, yeni durumu okuma, durdurma, başlangıç türü ve listeleme | Geçti |
| 2 | Üç hedefte eşleşen, eşleşmeyen ve eksik registry değeri | Geçti |
| 3 | Sayı ve metin registry türlerinde otomatik karşılaştırma | Geçti |
| 4 | Eksik registry değerinin Eşit değil koşulunu sağlamaması | Geçti |
| 5 | Tümü seçeneğinde bir yanlış kontrolün işlemi engellemesi | Geçti |
| 6 | Herhangi biri seçeneğinde tek doğru kontrolün yeterli olması | Geçti |
| 7 | Herhangi biri doğru olsa da okuma hatasının işlemi durdurması | Geçti |
| 8 | Koşul sağlanmazsa durdur; sonraki hedefin bağımsız devam etmesi | Geçti |
| 9 | İşlem hatasında hedefin kalan adımlarının başlamaması | Geçti |
| 10 | Yeniden başlatmada durdur, durmuş durumu gözle, başlat sırası | Geçti |
| 11 | İlk değişiklikten sonra iptal; yeni adım/hedefte değişiklik yapılmaması | Geçti |
| 12 | Eski ortak koşulun bir kez değerlendirilmesi ve kapsamının korunması | Geçti |
| 13 | Eksik onay, değişmiş önizleme ve önizlemeden vazgeçmede iş başlamaması | Geçti |
| 14 | Yanıltıcı başarı ve yanlış hedef kanıtının bağımsız kontrolle reddedilmesi | Geçti |
| 15 | Başlangıç türü değişikliğinin sonraki koşulda okunması | Geçti |
| 16 | Registry anahtarı ve servis varlığına göre doğru hedef seçimi | Geçti |
| 17 | Bozuk gerçek sayısal registry verisinin hata sayılması | Geçti |

## Yanıltıcı başarı kontrolü

14. senaryoda model bilerek başarılı dönüş kodu verdi fakat servis durumunu değiştirmedi. Gerçek çalıştırıcı Success satırı üretti. Kabul doğrulayıcısı gerçek son durum bekleneni karşılamadığı için bu kanıtı reddetti. Ayrıca kopyalanmış kanıtta yanlış hedef kimliği de reddedildi. Bu negatif kontrolün geçmesi, yanıltıcı başarının yakalandığı anlamına gelir.

## Bağımsız kanıt kontrolü

16 çalışmanın CSV, ledger ve terminal checkpoint kayıtları bağımsız olarak okundu. İlk zincirin servis başlatmadan sonra yeni durumu okuduğu, yeniden başlatmanın Stop ile Start arasında Stopped durumunu gözlemlediği doğrulandı. İki bozulmuş gerçek zincir kanıtı reddedildi. Ayrıntılar V27_INDEPENDENT_REVIEW.json içindedir.

## Kapsam dışında kalanlar

Gerçek registry sağlayıcısından okuma ve tür çözümleme, CIM/DCOM/SMB/PsExec bağlantısı, domain hesabı/parola, güvenlik duvarı veya EDR davranışı sınanmadı. Dosya/paket işlemleri bu kabul matrisine dahil değildir. WPF denetim olayları programla tetiklendi; fare/klavye erişilebilirlik testi değildir. İptalde gerçek iptal dosyası mekanizması kullanıldı; Durdur düğmesinin onay iletişim kutusu otomatik tıklanmadı. Fonksiyon engelleri işletim sistemi düzeyinde ağ güvenlik duvarı veya ağ trafiği kaydı değildir. Bellek değeri örneklenmiş çalışma belleğidir; kesin üst sınır değildir.

## Tekrar çalıştırma

Kökte HAFIF_TEST_CALISTIR.bat dosyasını açın. Yönetici yetkisi veya sanal makine kurulumu gerekmez. Sonuçlar docs/v27-offline-acceptance altında yeni tarihli klasöre yazılır. Uygulamanın kişisel katalog/profil ve gerçek çalışma yolları testte kullanılmaz; geçici dizine yönlendirilir.

Bu teslimin kabul sonucu acceptance-02 klasöründedir. Ön geliştirme koşularında test aracının dosya paylaşımı okuma yarışı giderildi; bu denemeler ayrı klasörlerde tutulmuştur. Üretim kodunda düzeltme yapılmadı.
