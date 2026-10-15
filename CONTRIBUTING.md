# Katkı ve doğrulama

- Uygulama Windows PowerShell 5.1 ve WPF kullanır. PowerShell kaynaklarında UTF-8 BOM ve mevcut Windows uyumluluğunu koruyun.
- Değişikliği mevcut akışlarla sınırlayın; veri kökü ve AppData katalog/profil yollarını kendiliğinden değiştirmeyin.
- Önce `tests\Invoke-OfflineValidation.ps1` çalıştırın. Bu tur 12 güvenli yerel regresyon dosyasını, hafif kabul senaryolarını ve bağımsız kanıt kontrolünü yürütür. Geniş `Invoke-RegressionTests.ps1` tarihsel testleri de içerir; bazıları erişilemeyen adlara bağlantı denemesi yapabildiğinden çevrimdışı tur yerine kullanılmaz.
- `-RunLive` isteyen araçlar yönetici yetkisiyle gerçek yerel kaynaklara erişir; CI veya sıradan regresyon turuna eklemeyin.
- README, kullanım kılavuzu ve VERSION.json tamamlanan teslimi aynı şekilde anlatmalıdır.
- Profil, parola, gerçek hedef listesi, şirket paketi, toplanmış dosya veya operasyon logu commit etmeyin. Örneklerde `PC-TEST`, `server\share` ve geçici fixture kullanın.
- PsExec.exe repo dışı bağımlılıktır. Kendi indirdiğiniz kopyayı köke yerleştirebilirsiniz; `.gitignore` bunu yayına dahil etmez.

Sorun bildirirken operasyon, beklenen/gerçek davranış ve kişisel veriler temizlenmiş hata metni yeterlidir. Gerçek UNC adreslerini, bilgisayar adlarını ve kimlik bilgilerini paylaşmayın.
