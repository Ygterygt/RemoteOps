# RemoteOps teslim kuralları

Kullanıcının kalıcı isteği: tamamlanan her değişiklik tesliminde sürümü bir artır ve ZIP olarak Google Drive'a yükle.

- Güncel sürüm kökteki VERSION.json içindedir. Ara kod düzenlemeleri için ayrı sürüm üretme; tamamlanan teslim başına bir artır.
- Önceki dağıtımı koru; yeni sürümü YD_RemoteOps.App_v<N> klasöründe hazırla ve aynı isimli ZIP üret.
- Kod, kılavuzlar, ekran görüntüleri ve doğrulama kayıtları aynı teslimi anlatmalı. Testlerin kapsamını ve gerçek canlı testleri birbirinden ayır.
- ZIP'i son doğrulamadan sonra oluştur; arşiv bütünlüğünü kontrol et. Drive'a yeni sürüm dosyası olarak yükle, önceki sürümün üzerine yazma. Aynı teslimin düzeltmesi için kendi dosya kimliğini kullan.
- Yükleme sonrasında Drive dosya kimliğini ve boyutunu doğrula; kullanıcıya gerçek bağlantıyı bildir. Yükleme başarısızsa açıkça belirt.
- Dağıtım adı değişse de C:\Temp\YD_RemoteOps.App ve kullanıcının AppData katalog/profil yollarını değiştirme.
- Mevcut işleyişi koru; gerçek hedef değişikliklerini yalnızca açıkça yetkilendirilmiş kapsamda yap.
