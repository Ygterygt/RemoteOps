# RemoteOps

![Version: 28](https://img.shields.io/badge/version-v28-0A8C83)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4)
![PowerShell: 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE)

Tek operatörün yazılım dağıtımı ve uzak bilgisayar operasyonları için Windows PowerShell 5.1 / WPF uygulaması. **Güncel kabul edilen sürüm v28'dir.**

![Adım sonuçları — yerel örnek veri](docs/screenshots-v28/v28-adim-sonuclari.png)

[v28 sürüm sayfası](https://github.com/Ygterygt/RemoteOps/releases/tag/v28) · [Tam v28 ZIP paketi — Google Drive](https://drive.google.com/file/d/1yEC8havMfPkcBlYaR_tYw_yGWCHpuqUG/view?usp=drivesdk)

## Güncel sürüm

v28, servis/registry/dosya gönderiminden sonra beklenen sonucu otomatik doğrular. Komut yanıtı ve doğrulama sonucu ayrı gösterilir; beklenen durum oluşmazsa veya kesinleştirilemezse ilgili hedefin sonraki reçete adımları durur. Tamamlanmış işlemler otomatik geri alınmaz. İşlem adları otomatik oluşur; koşullar ilgili adımın içinde düzenlenir. Registry türü seçmek gerekmez. Reçete ekranında Adımlar ve Hedefler ayrı sekmelerdedir; işlem ve çalışma koşulu ayrı düzenleme penceresinde açılır.

- Servis/registry koşulları; Tümü / Herhangi biri; koşul sağlanmazsa adımı atlama veya hedefi durdurma.
- Önceki reçetelerin özel adları ve ortak koşullarının tek değerlendirme davranışı korunur.
- Ortak hedef düzenleme, sonuç filtreleri ve seçili sonuçtan teşhis/geri almaya geçiş.
- Kayıtlı paketler; dosya, registry, servis/görev, süreç ve envanter işlemleri; HTML/CSV raporlama.

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| Durumu değişen yerel hedef modeliyle operasyon senaryoları | 19/19 geçti |
| Güvenli yerel regresyon dosyaları | 22/22 geçti |
| Model sınırı negatif kontrolleri | 5/5 geçti |
| Bağımsız CSV/ledger/checkpoint incelemesi | 18 çalışma doğrulandı |

Gerçek WPF denetimleri, istek oluşturma, ayrı koordinatör ve çocuk süreçleri kullanıldı. Komut başarılı döndüğü halde durumun değişmediği ve okuma hatasının son durumu belirsiz bıraktığı senaryolarda sonraki adımların durduğu doğrulandı. Kabul koşusu yaklaşık 204 saniye sürdü; örneklenen toplam çalışma belleği yaklaşık 687 MiB idi. Sanal makine kullanılmadı.

Bu sonuçlar gerçek ağ, Windows registry sağlayıcısı, domain yetkileri, SMB/PsExec veya güvenlik yazılımlarının doğrulandığı anlamına gelmez. Uzak erişim sınırları yalnızca geçici test kopyasında yerel modele yönlendirilir. İptal mekanizması sınanır; onay iletişim kutusunun fareyle tıklanması sınanmaz.

[v28 test raporu](docs/V28_TEST_RAPORU.md) · [Özet kayıt](docs/V28_TEST_SUMMARY.json) · [Kod incelemesi](docs/V28_CODE_REVIEW.json)

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

Reçete kabul testi için kökteki **HAFIF_TEST_CALISTIR.bat** dosyasını açın. PsExec, sanal makine veya yönetici yetkisi gerekmez. Yeni sonuçlar `TestResults/Offline` altında oluşur.

22 regresyon dosyası ve 19 kabul senaryosunu birlikte çalıştırmak için:

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
