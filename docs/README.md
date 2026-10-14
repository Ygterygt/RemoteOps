# RemoteOps doküman dizini

14 Ekim 2026 · YD_RemoteOps.App_v11

Şirket pilotundan önce kullanım için kılavuzu, sistemin tamamını anlamak için teknik el kitabını okuyun. Markdown kaynaklar ve PDF'ler aynı güncel yapıyı anlatır. Görseller örnek verilerle gerçek WPF arayüzünden üretilmiştir.

| Doküman | İçerik | PDF |
| --- | --- | --- |
| [Kullanım kılavuzu](KULLANIM_KILAVUZU.md) | Dört sekme, profil, paket, downgrade, durdurma, sonuç okuma ve ekranlar. | [Kılavuz](../KULLANIM_KILAVUZU.pdf) |
| [Teknik el kitabı](TEKNIK_EL_KITABI.md) | Bütün dosyalar, süreç/hesaplar, uzak yöntemler, 26 operasyon, veri yolları, sınırlar ve bakım. | [El kitabı](RemoteOps_Teknik_El_Kitabi.pdf) |
| [Çalışma mantığı](CALISMA_MANTIGI.md) | Mimari ve paket akışının kısa açıklaması. | [Akış rehberi](RemoteOps_Calisma_Mantigi.pdf) |
| [İnceleme raporu](INCELEME_RAPORU.md) | Güncel yerel doğrulamalar, bilinen test referans sorunu ve pilot sınırı. | [İnceleme](RemoteOps_Inceleme_Raporu.pdf) |
| [Gelecek operasyon tasarımı](GELECEK_OPERASYON_OLUSTUR.md) | Henüz uygulanmamış genel reçete motoru; mevcut paket yönetiminden farkı. | [Tasarım](RemoteOps_Operasyon_Olustur_Tasarim.pdf) |
| [Pilot kontrolü](PAKET_YONETIMI_PILOT_KONTROLU.md) | Şirket testinde doldurulacak kabul senaryoları. | Markdown kayıt tablosu. |
| [Paket geliştirme planı](PAKET_YONETIMI_GELISTIRME_PLANI.md) | Uygulanmış paket tasarımının kararı ve kapsamı. | Markdown tasarım kaydı. |

## Dağıtım ve veri

Kökteki YD_RemoteOps.App.bat, ayrıca indirilen PsExec.exe, Modules içindeki altı modül ve RemoteOps.App içindeki BAT/yedi PS1 dosyası birlikte tutulur. tests ve docs çalışma bağımlılığı değildir, geliştirme ve operatör desteğidir. Eski MD_Script.ps1, CLM runner ve örnek Plugins bu dağıtımda yoktur. Windows PowerShell 5.1/FullLanguage ve WPF varsayılır; gerçek şirket ağı uyumluluğu pilotla doğrulanacaktır.

Runtime veri kökü C:\Temp\YD_RemoteOps.App; kişisel profiller/ayarlar/katalog %APPDATA%\MDRemoteOps altındadır. Dağıtım klasörü adını değiştirmek bu yolları değiştirmez. Paylaşımda kişisel profil/parola, şirket çıktıları ve yedekler pakete eklenmemelidir. Paket kaynakları UNC üzerinde ayrıca hazırlanır.

## Doküman bakımı

PDF üreticisi tools/build_documents.py, ekran üreticisi tools/capture_documentation.ps1'dir. Paket görselleri tests/RemoteOps.PackageLibraryUi.Tests.ps1 -PreviewDirectory docs/paket-ui-preview ile üretilir. Yerel test kayıtları DOKUMAN_DOGRULAMA_TESTLERI.csv içindedir. Yerel geliştirme notları, ham operasyon kanıtları ve PDF render ara dosyaları public repoya dahil değildir.

14 Ekim kapsamlı güvenilirlik denetimi: [bulgular ve doğrulamalar](INCELEME_RAPORU.md), [tam test çıktısı](KAPSAMLI_TEST_SONUCLARI.csv). Güncel v11 regresyon turu toplam 50 test dosyasını kapsar.


v10 güncellemesi: [yerel canlı test raporu](CANLI_TEST_RAPORU.md), 18/18 gerçek senaryo ve temizlik kanıtı. Bu kayıt v10 canlı testinin tarihsel kanıtıdır.


v11: ortak işlem öncesi erişim, sarı erişilemedi sonuçları ve sürümsüz script regresyonu. [Salt okunur yerel bağlantı kanıtı](live-test-v11/ACCESS_LIVE_TEST.json): 26/26; önceki v10 mutasyon testinden ayrıdır. Dağıtım sürümü [VERSION.json](../VERSION.json) içindedir; sonraki tamamlanan teslimler bir artırılarak yeni ZIP halinde Drive'a yüklenir.

GitHub kaynak yayını [üçüncü taraf notlarına](../THIRD_PARTY_NOTICES.md) tabidir: PsExec.exe ayrı indirilir. Public test JSON/CSV özetlerinde bilgisayar adı ve yerel yollar çıkarılmıştır; uygulama kaynakları v11 ile aynıdır.
