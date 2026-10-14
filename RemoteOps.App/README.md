# RemoteOps uygulama kaynakları

14 Ekim 2026 · YD_RemoteOps.App_v11

Windows PowerShell 5.1/WPF uygulaması. Kökteki YD_RemoteOps.App.bat ile başlatılır. Paketlerim, Paket Oluştur, Operasyon ve Rapor sekmeleri; 26 yerleşik operasyon ve ayrı Runner süreçleri vardır. Hazır UNC script tanımları kaydedilir; MSI/EXE veya script üretimi yapılmaz.

Güncel [doküman dizini](../docs/README.md), [kullanım kılavuzu](../docs/KULLANIM_KILAVUZU.md), [teknik el kitabı](../docs/TEKNIK_EL_KITABI.md), [çalışma mantığı](../docs/CALISMA_MANTIGI.md) ve [pilot kontrolü](../docs/PAKET_YONETIMI_PILOT_KONTROLU.md) esas alınmalıdır.

Main mevcut Windows token'ını kullanır. Alternatif profil credential API ile açılan süreçte çalışır; parola CLI/request içinde yoktur. Hedef paket PsExec SYSTEM ile çalışır. Profiller/ayarlar/katalog %APPDATA%\MDRemoteOps, çıktılar C:\Temp\YD_RemoteOps.App altındadır. Klasör yeniden adlandırılması veri yollarını değiştirmez.

App.ps1 GUI, PackageUi.ps1 paket ekranları, Runner.ps1 dispatch/worker, Packages.ps1 şema/katalog, Deployment.ps1 dağıtım durumu, RunState.ps1 iptal/checkpoint, Reports.ps1 raporlardır. Modules içindeki altı dosya birlikte tutulur. Eski MD/CLM ve örnek Plugins bu dağıtımda yoktur; eklenti keşif altyapısı isteğe bağlıdır.

Kontrollü downgrade yeni sürümde iki kaynağı önceden doğrular; kaldırma/yokluk/kurulum/tam sürüm kontrolü yapar. Otomatik reboot, retry veya geri kurulum yoktur. Durdur kaydedilmiş dağıtımda adımlar arasında iptal ister; Zorla durdur yerel süreç ağacını kapatır, uzak iş devam edebilir. Belirsiz sonuç manuel doğrulanır.

Eski iki test mevcut dağıtım kapsamına uyarlandı; güncel yerel doğrulama 50/50 test dosyası geçişidir. Günlük rapor paket/eylem bazında terminal hedef sayımlarını gösterir. [Güncel inceleme](../docs/INCELEME_RAPORU.md) ayrıntıyı açıklar. İlk şirket pilotu geri bildirimi işlendi; tam kabul matrisi tamamlanmadı; FullLanguage çalışma varsayımıdır.

14 Ekim düzeltmeleri: manuel tanımı editöre aktarırken düğme/alan ayrımı; paket sonuç HTML'inde tek hedef özeti ve ayrı adım ayrıntıları; tüm operasyonlar için ortak canlı hedef tablosu. 50010 kaynağı ayrıca loglarla araştırılmalıdır.

GitHub kaynak yayını PsExec.exe içermez; üçüncü taraf bağımlılığı kökteki README üzerinden ayrı indirilir. Ham yerel test kayıtları yerine kişisel alanları çıkarılmış sonuç özetleri yayımlanır.
