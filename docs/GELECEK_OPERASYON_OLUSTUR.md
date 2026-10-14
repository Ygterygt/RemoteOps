# Gelecek Operasyon Oluştur tasarımı

14 Ekim 2026 · YD_RemoteOps.App_v11 · Henüz uygulanmamış tasarım

Mevcut Paket Oluştur/Paketlerim ve kontrollü downgrade uygulanmıştır. Bu belge gelecekte düşünülen genel amaçlı çok adımlı operasyon reçetesini anlatır; mevcut arayüzde böyle bir reçete editörü veya motoru yoktur. Güncel davranış için teknik el kitabı esas alınmalıdır.

## 1. Mevcut ve gelecek kapsam

| Özellik | Durum |
| --- | --- |
| Hazır UNC kurulum/kaldırma tanımı kaydetme | Mevcut. |
| Kişisel paket kütüphanesi, kopya, import/export | Mevcut. |
| Kontrollü downgrade ve kısmi dağıtım raporu | Mevcut. |
| Kod yazmadan servis/dosya/registry/paket adımlarını birleştirme | Gelecek tasarım. |
| Paylaşılan ekip kataloğu/merkezi kilit/onay | Henüz uygulanmadı. |

## 2. Amaç ve örnek

Operatör test edilmiş yapı taşlarından bir form ve adım listesi oluşturabilir. Örnek: test uygulamasının servisini durdur, config dosyasını yedekle/gönder, servisi başlat, sağlık kontrolü yap. Bu örnek uygulamada bugün çalıştırılabilen bir tarif değildir.

```text
Form: Hedefler + config kaynağı
1. Servis durumunu oku ve kaydet
2. Servisi durdur
3. Config yedekle / değiştir
4. Servisi başlat
5. Config ve servis durumunu doğrula
```

## 3. Önerilen veri ve yürütme sözleşmesi

Tarif şeması ayrı sürümlenmiş kimlik/revizyon, parametre tanımları, izin verilen adım türleri, koşullar ve hata politikası taşımalıdır. Profil/parola ve hedef listesi tarifte saklanmamalıdır. Çalıştırmada bağımsız snapshot, hedef başına sonuç ve ortak OperationID kullanılmalıdır. Serbest PowerShell metni yerine doğrulanmış adım türleri tercih edilir; script eklentileri ayrı güven sınırıdır.

Mevcut Deployment motoru tespit/kaynak/execute callback modelini, RunState checkpoint düzenini ve Reports terminal sonuç sözlüğünü örnek sağlar. Genel reçeteye geçişte bunlar yeni şemaya körlemesine bağlanmamalı; adım başına geri alma ve kesinti sınırı ayrıca tasarlanmalıdır.

## 4. Hata ve geri alma kuralları

Her adım ön koşul, mutasyon, son koşul ve varsa geri alma manifestini açıkça tanımlamalıdır. Geri alınamayan process kill, task run ve yazılım kaldırma gibi adımlar arayüzde açıklanmalıdır. Sonraki adımın hatası önceki adımları otomatik başarılı veya geri alınmış gibi göstermemelidir. Timeout ve force stop belirsiz sonucunu korumalıdır.

Varsayılan hata politikası durdur ve raporla olabilir. Otomatik retry/reboot/geri kurulum ayrıca tasarım ve şirket pilotu gerektirir. Merkezi kilit olmadan farklı operatör bilgisayarlarının aynı hedefte reçete yürütmesi çakışabilir.

## 5. Arayüz ve kabul kriterleri

Önerilen ekran: adım listesi, seçili adım formu, etki/ön koşul özeti ve çalıştırma önizlemesi. İleri özelliklerden önce erişilebilir kaydetme/çalıştırma kontrolleri ve 125% ölçek testleri yapılmalıdır. Import/export önizleme ve revizyon çakışması mevcut paket kütüphanesindeki ilkelere uymalıdır.

Kabul testleri şema/parametre sınırları, sırayla yürütme, hata sonrası durma, rollback kapsamı, belirsiz sonuç, iptal/checkpoint ve hedef başına tek terminal ledger kaydını içermelidir. İlk şirkete taşıma aşamasında bu motoru eklemek yerine mevcut paket pilotundan çıkan ihtiyaçlarla kapsam yeniden değerlendirilir.

## 6. Öncelik

Eski iki test referansı ve günlük paket/eylem kırılımı canlı test öncesinde tamamlandı. Sonraki kararlar şirket pilotu ve gerçek paket/hesap erişim sonuçlarına göre alınacak. Genel reçete motoru ayrı onaylanacak geliştirme kapsamıdır. Bu belge bir uygulama veya otomatik yürütme taahhüdü değildir.
