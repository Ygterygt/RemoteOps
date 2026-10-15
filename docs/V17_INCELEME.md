# v17 — Birleşik Geri Alma Merkezi

15 Ekim 2026 · YD_RemoteOps.App_v17 · Önceki sürüm: v16

## Teslim kapsamı

Sekizinci sekme; dosya/klasör geri yükleme, dosya taşıma/değiştirme geri alma, registry, servis ve zamanlanmış görev manifestlerini tek listede gösterir. Bilgisayar/tür/kullanılabilirlik/tarih filtreleri, 50 kayıtlık sayfalama, ayrıntılar ve işlem öncesi hesap/kapsam özeti eklendi. Tek manifest + bilgisayar + tür kapsamının bütün nesneleri seçilir.

Eksik/bozuk yedekler çalıştırılamaz. RESTORE veya ROLLBACK elle yazılır. Sabit kayıt/entry kimlikleri, manifest hash'i ve gerekli yerel yedek kontrolleri UI ve Runner kapılarında yinelenir. Yeni merkez sayı tabanlı yedek seçimine dayanmaz. Var olan görev ezilmez. Eski Operasyon sekmesi girişleri korunur.

## Doğrulama

- Başlangıç: 64/64 bağımsız test dosyası.
- Son tam tur: 67/67 test dosyası geçti. Son ASCII sürücü yolu düzeltmesinden sonra üç etkilenen test dosyası ayrıca geçti; en güncel günlükler teslimdedir. [Sonuçlar](V17_TEST_RESULTS.csv), [test günlükleri](v17-test-logs/RemoteOps.RecoveryRunner.Tests.ps1.txt).
- Sözdizimi: 98 PowerShell dosyası, 0 hata. [Ayrıntılar](V17_PARSE_RESULTS.csv).
- Yeni indeks testi: beş tür, iki bilgisayar, karışık türler, sabit/sıra bağımsız kimlikler, QWORD/MULTI_SZ/HKU ve boş metin, eksik değer alanı, bozuk/eksik yedek, DTD, farklı hedef UNC, kök dışı yol, junction, tarihler ve literal filtre.
- Yeni adapter testi: gerçek seçici/adapter ve dosya geri alma döngüleri; CIM/SMB yazma sınırları sahte. Doğru bilgisayar/tür, eski QWORD/SID, mevcut görev koruması, değişmiş manifest ve yanlış onay/hedef/operasyonda sıfır mutasyon. Gerçek CSV yazıcısında başarı/hata sonuçları korunur.
- Yeni WPF testi: sekme/liste, tam kapsam, vazgeç, elle onay, değişmiş hesap, kayıp seçim, eski manifest ve yalnız bir kez dispatch.
- Beş PDF ve normal/%125 ölçekli örnek WPF görselleri üretildi, render edilerek gözle kontrol edildi.
- Gerçek uç noktada canlı geri alma testi yapılmadı. Tarihsel canlı testler v17 kabulü değildir.

## Bağımsız inceleme düzeltmeleri

| Bulgu | Doğrulanan düzeltme |
| --- | --- |
| İç içe sonuç dizisi dosya rollback CSV alanlarını kaybediyordu | Düz sonuç dizisi; gerçek CSV'de bilgisayar/başarı/hata ayrımı |
| OldExists=True kaydında OldValue alanının yokluğu boş yazıya dönüşüyordu | Alan zorunlu; açık boş metin geçerli |
| Servis/görev mutasyonlarında son kapsam doğrulaması eksikti | Oturumdan ve mutasyondan önce callback; eski manifestte yazma yok |

Ayrıca Türkçe kültürde ASCII bilgisayar adı ve I sürücüsü doğrulaması ve kaydırılabilir kapsam metni doğrulandı. İnceleme salt okunur yapıldı, gerçek hedefe bağlanılmadı.

## Sınırlar ve dağıtım

Yerel kullanılabilirlik canlı hedef garantisi değildir. Büyük yedeklerin tamamı indekslemede hash'lenmez; bütün içerik için kriptografik bütünlük/atomiklik iddiası yoktur. Dosya restore aynı adlı içeriği ezebilir; dizindeki fazladan hedef dosyalarını silmez. Daha sonraki servis/registry değişiklikleri eski duruma dönüldüğünde etkilenebilir. Tümünü geri al, otomatik tekrar/zincir ve nesne alt seçimi yoktur. Mevcut 22.000 karakterlik istek sınırı geçerlidir; çok büyük kapsamın başlatılması bu sınır nedeniyle reddedilebilir.

v16 klasörü ve ZIP'i korunur. Runtime C:\Temp\YD_RemoteOps.App ve %APPDATA%\MDRemoteOps yolları değişmez. ZIP son doğrulamadan sonra oluşturulur; her girdinin SHA-256 ve arşiv CRC denetimi yapılır. Drive yüklemesi yapılmaz.

[Geri Alma Merkezi ekranı](screenshots-v17/geri-alma-merkezi.png) · [%125 ekran](screenshots-v17/geri-alma-merkezi-125.png) · [Önizleme](screenshots-v17/geri-alma-onizleme.png) · [Eksik yedek](screenshots-v17/eksik-yedek.png)
