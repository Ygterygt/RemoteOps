# Değişiklikler

## v27 - 15 Ekim 2026

- Güncel kabul edilen sürüm v27. v26 uygulama kodu korunarak hafif kabul testi ve doğrulama kayıtları eklendi.
- Otomatik adlandırılan adımlar, adımın içinde koşul, sabit reçete ekranı ve ayrı işlem/çalışma koşulu düzenleyicisi.
- Otomatik registry türü karşılaştırması, bağlama göre servis kontrolleri, All/Any, atlama/durdurma ve mevcut reçete uyumluluğu.
- Tek operatör için ortak hedef araçları, sonuç filtreleri, teşhis ve geri alma geçişleri.
- 17/17 çevrimdışı operasyon senaryosu, 12/12 güvenli yerel regresyon ve beş negatif sınır kontrolü geçti. 16 çalışma kaydı bağımsız doğrulandı.
- Tek komutla çevrimdışı doğrulama turu eklendi. Gerçek ağ, registry sağlayıcısı ve domain ortamı test edilmiş sayılmaz.
- Önceki dağıtımlar ve Git geçmişi korunur. Üçüncü taraf PsExec ikilisi kaynak repoya dahil edilmez.

## v11 — 14 Ekim 2026

- Bütün operasyonlara işlem öncesi ortak SMB/WMI erişim kontrolü.
- Erişilemeyen hedefler için WPF, HTML grafik, günlük rapor ve paket kırılımlarında sarı sınıflandırma.
- Yetki hataları ve gerçek işlem hatalarının kırmızı olarak korunması.
- Kontrolsüz kayıtlı scriptlerin sürüm ve uygulama kimliği olmadan çalışmasının doğrulanması.
- SMB ön kontrolünün tamamında zaman sınırı ve geçersiz operasyon/eklenti doğrulamasının bağlantı öncesine alınması.
- 50/50 otomatik regresyon; 26/26 salt okunur yerel erişim kontrolü.

İlk GitHub yayını v11 kaynaklarını korur; kök README ve public test özetleri depo sunumu için hazırlanmıştır.

## v10

- Operasyon girişlerine kısa kullanım örnekleri.
- Çalıştırma ve istemci bazında çekilen dosya/log kısayolları.
- Türkçe kültür ASCII `I` doğrulaması ve DCOM görev silme uyumluluğu düzeltmeleri.
- 18/18 geçici kaynaklı yerel operasyon ve geri alma senaryosu.
