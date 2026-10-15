# RemoteOps

![Version: 27](https://img.shields.io/badge/version-v27-0A8C83)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4)
![PowerShell: 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE)

Tek operatörün yazılım dağıtımı ve uzak bilgisayar operasyonları için Windows PowerShell 5.1 / WPF uygulaması. **Güncel kabul edilen sürüm v27'dir.**

![Operasyon reçeteleri](docs/screenshots-v26/recete-ana.png)

## Güncel sürüm

v27, v26 uygulama kodunu korur ve hafif operasyon kabul testini ekler. İşlem adları otomatik oluşur; koşullar ilgili adımın içinde düzenlenir. Registry türü seçmek gerekmez. Reçete ekranında Adımlar ve Hedefler ayrı sekmelerdedir; işlem ve çalışma koşulu ayrı düzenleme penceresinde açılır.

- Servis/registry koşulları; Tümü / Herhangi biri; koşul sağlanmazsa adımı atlama veya hedefi durdurma.
- Önceki reçetelerin özel adları ve ortak koşullarının tek değerlendirme davranışı korunur.
- Ortak hedef düzenleme, sonuç filtreleri ve seçili sonuçtan teşhis/geri almaya geçiş.
- Kayıtlı paketler; dosya, registry, servis/görev, süreç ve envanter işlemleri; HTML/CSV raporlama.

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| Durumu değişen yerel hedef modeliyle operasyon senaryoları | 17/17 geçti |
| Güvenli yerel regresyon dosyaları | 12/12 geçti |
| Model sınırı negatif kontrolleri | 5/5 geçti |
| Bağımsız CSV/ledger/checkpoint incelemesi | 16 çalışma doğrulandı |

Gerçek WPF denetimleri, gerçek istek oluşturma, koordinatör ve 48 çocuk süreç kullanıldı. Yanıltıcı Success raporu hedef durumu ayrıca kontrol edilerek yakalandı. Kabul koşusu yaklaşık 149 saniye sürdü; örneklenen toplam çalışma belleği yaklaşık 700 MiB idi. Sanal makine kullanılmadı.

Bu sonuçlar gerçek ağ, Windows registry sağlayıcısı, domain yetkileri, SMB/PsExec veya güvenlik yazılımlarının doğrulandığı anlamına gelmez. Uzak erişim sınırları yalnızca geçici test kopyasında yerel modele yönlendirilir. İptal mekanizması sınanır; onay iletişim kutusunun fareyle tıklanması sınanmaz.

[Kabul raporu](docs/V27_HAFIF_TEST_RAPORU.md) · [Özet kayıt](docs/V27_TEST_SUMMARY.json) · [Bağımsız inceleme](docs/V27_INDEPENDENT_REVIEW.json)

## Hızlı başlangıç

1. Repoyu indirin veya klonlayın:

   ```powershell
   git clone https://github.com/Ygterygt/RemoteOps.git
   cd RemoteOps
   ```

2. Windows PowerShell 5.1, WPF ve FullLanguage çalışma ortamını kullanın.
3. Paket çalıştırmak için [Microsoft Sysinternals PsExec](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec) indirin ve `PsExec.exe` dosyasını köke yerleştirin veya PATH üzerinden erişilebilir yapın. Üçüncü taraf ikili bu repoda dağıtılmaz.
4. `YD_RemoteOps.App.bat` dosyasını açın, çalışma hesabını ve hedefleri seçin.

Gerçek operasyonlarda uygun yönetim yetkileri ve operasyonun gerektirdiği ağ erişimi bulunmalıdır. Uygulama verileri `C:\Temp\YD_RemoteOps.App`, kişisel kataloglar/profiller `%APPDATA%\MDRemoteOps` altında kalır.

## Canlı hedef kullanmadan test

Reçete kabul testi için kökteki **HAFIF_TEST_CALISTIR.bat** dosyasını açın. PsExec, sanal makine veya yönetici yetkisi gerekmez. Yeni sonuçlar `docs/v27-offline-acceptance/Run-*` altında oluşur.

12 regresyon ve 17 kabul senaryosunu birlikte çalıştırmak için:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Invoke-OfflineValidation.ps1
```

Diğer test dosyalarının kapsamı farklı olabilir; canlı test araçlarını normal çevrimdışı doğrulama turuna dahil etmeyin. GitHub'daki kabul kanıtları sentetik hedefler içerir ve çalışma bilgisayarına ait dosya yolları temizlenmiştir.

## Belgeler

- [Kullanım kılavuzu](docs/KULLANIM_KILAVUZU.md) · [PDF](KULLANIM_KILAVUZU.pdf)
- [Teknik el kitabı](docs/TEKNIK_EL_KITABI.md)
- [Çalışma mantığı](docs/CALISMA_MANTIGI.md)
- [Değişiklikler](CHANGELOG.md)
- [Üçüncü taraf bağımlılıklar](THIRD_PARTY_NOTICES.md)

Eski sürümler Git geçmişinde korunur. Kaynak arşivi PsExec içermez.
