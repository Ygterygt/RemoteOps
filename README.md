# RemoteOps

[![Regression: 50 passing](https://img.shields.io/badge/regression-50%20passing-17855A)](docs/KAPSAMLI_TEST_SONUCLARI.csv)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4)
![PowerShell: 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE)
![Version: 11](https://img.shields.io/badge/version-v11-0A8C83)

Şirket içi yazılım dağıtımı ve uzak bilgisayar operasyonları için Windows PowerShell 5.1 / WPF uygulaması. Tekrarlanan paket tanımlarını kaydeder; işlem, sonuç ve log takibini aynı arayüzde toplar.

![RemoteOps günlük rapor](docs/rapor.png)

## Neler yapar?

- **Paketlerim:** UNC üzerindeki hazır scriptleri kurulum, kaldırma ve bağımsız eski sürüme dönüş tanımlarıyla kaydeder ve çağırır.
- **Paket Oluştur:** kategori, uygulama kimliği, hedef sürüm ve işlem kaynaklarını tanımlar. Kontrolsüz tetikleme ile sürüm/uygulama kimliği olmadan kişisel scriptler çalıştırılabilir.
- **Operasyon:** dosya, registry, servis, zamanlanmış görev, süreç ve envanter işlemlerini yürütür. Giriş alanlarında kısa örnekler bulunur.
- **Rapor:** çalıştırma ve istemci bazında sonuç, HTML/CSV çıktı, toplanan loglar ve çekilen dosyalar için kısayollar sunar.
- **Erişim kontrolü:** her hedefte işlem başlamadan gerekli SMB veya WMI/DCOM bağlantısını sınar. Erişilemeyenler sarı **Atlandı — Erişilemedi**; yetki ve gerçek işlem hataları kırmızı gösterilir. Ping zorunlu değildir.

Uygulama MSI/EXE veya kurulum scripti üretmez; önceden hazırlanmış `.bat`, `.cmd`, `.ps1`, `.vbs` dosyalarını çalıştırır.

## Hızlı başlangıç

1. Repoyu indirin veya klonlayın:

   ```powershell
   git clone https://github.com/Ygterygt/RemoteOps.git
   cd RemoteOps
   ```

2. **Windows PowerShell 5.1**, WPF ve `FullLanguage` çalışma ortamını kullanın. Hedef operasyon için gerekli yönetim izinleri ve SMB/RPC/DCOM erişimi bulunmalıdır.
3. Paket çalıştırma için [Microsoft Sysinternals PsExec](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec) indirin. `PsExec.exe` dosyasını repo köküne yerleştirin veya PATH üzerinden erişilebilir yapın. Üçüncü taraf ikili bu repoda dağıtılmaz.
4. Kökteki `YD_RemoteOps.App.bat` dosyasını başlatın.
5. Çalışma hesabını seçin, paket veya operasyon tanımını doldurun ve hedef bilgisayarları girin.

Paketler mevcut uzak çalışma mekanizmasıyla **SYSTEM** hesabında yürütülür. Kaynak UNC paylaşımının hedef SYSTEM bağlamından okunabilmesi gerekir. Ayrıntılar [kullanım kılavuzundadır](docs/KULLANIM_KILAVUZU.md).

## Sonuçları okuma

![Erişilemeyen tek hedefin HTML raporu: sarı yüzde 100, hata sıfır](docs/paket-ui-preview/sonuc-dagilimi-v11.png)

Erişilemeyen hedef atlanır ve sonuç listesinden kaybolmaz. CSV'de teknik `Unreachable` durumu korunur; ekran, grafik ve günlük rapor bunu sarı grupta toplar. İşlem başladıktan sonra sonucu belirsiz kalan dağıtımlar ayrıca değerlendirilir; otomatik başarı kabul edilmez.

## Dosya yapısı

```text
RemoteOps/
├── YD_RemoteOps.App.bat       # Başlatıcı
├── VERSION.json              # Uygulama sürümü
├── RemoteOps.App/            # WPF, Runner, paket motoru ve raporlar
├── Modules/                  # Dosya, registry, servis/görev, envanter worker'ları
├── tests/                    # Otomatik regresyon ve ayrı canlı test araçları
└── docs/                     # Kılavuzlar, ekranlar ve doğrulama özetleri
```

Çalışma verileri `C:\Temp\YD_RemoteOps.App`; kişisel profiller, ayarlar ve paket kataloğu `%APPDATA%\MDRemoteOps` altındadır. Repo klasörünü yeniden adlandırmak bu yolları değiştirmez. İşletim çıktıları ve kullanıcı profilleri Git'e eklenmez.

## Dokümanlar

| Doküman | İçerik |
| --- | --- |
| [Kullanım kılavuzu](docs/KULLANIM_KILAVUZU.md) · [PDF](KULLANIM_KILAVUZU.pdf) | Kurulum, ekranlar ve günlük kullanım |
| [Teknik el kitabı](docs/TEKNIK_EL_KITABI.md) | Bileşenler, uzak yöntemler, veri yolları ve sınırlar |
| [Çalışma mantığı](docs/CALISMA_MANTIGI.md) | İstekten hedef sonucuna akış |
| [Doğrulama raporu](docs/INCELEME_RAPORU.md) | Test kapsamı ve düzeltilen sorunlar |
| [Pilot kontrolü](docs/PAKET_YONETIMI_PILOT_KONTROLU.md) | Şirket ortamında kabul senaryoları |
| [Değişiklikler](CHANGELOG.md) | Sürüm özeti |

## Testler

Windows PowerShell 5.1 üzerinden:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Invoke-RegressionTests.ps1
```

v11 yerel doğrulaması: **50/50 otomatik test dosyası** ve **26/26 salt okunur yerel erişim kontrolü**. Önceki v10'da 18/18 geçici kaynaklı operasyon/geri alma senaryosu doğrulandı. Bunlar şirket ağı kabul testinden ayrıdır.

Normal regresyon turu `Invoke-RemoteOpsLocalLiveTest.ps1` ve `Invoke-RemoteOpsAccessLiveTest.ps1` araçlarını çağırmaz. Canlı araçlar açık `-RunLive` ve yönetici token ister. Public test özetlerinden bilgisayar adı, yerel kullanıcı yolları ve ham operasyon logları çıkarılmıştır.

## Geliştirme

[Katkı rehberi](CONTRIBUTING.md), [teslim kuralları](AGENTS.md) ve [üçüncü taraf notları](THIRD_PARTY_NOTICES.md) değişiklik öncesinde okunmalıdır. Uygulamanın kaynak sürümü **v11**'dir; bu ilk GitHub yayını çalışma davranışını değiştirmez.
