# v15 inceleme ve teslim özeti

15 Ekim 2026 · YD_RemoteOps.App_v15

Geçmiş ve Hata Teşhisi sekmeleri eklendi. Tarih/operasyon/bilgisayar/sonuç filtreleri, sayfalama, hedef sonuçları ve özgün adımlar, rapor/CSV/log bağlantıları, seçili hedefin log ve çekilen dosya klasörleri, önizlemeli yerel tanı ZIP'i vardır. Reçete, hedef grubu, önizleme ve birleşik geri alma sonraki teslimlerdir.

## Kanıt ve kapsam

Başlangıçta mevcut 57 test dosyası geçti. Yeni History, Diagnostics ve HistoryUi testleri eklendi; tam regresyon 60 test dosyasıdır. Sonuçlar V15_TEST_RESULTS.csv, tam test çıktıları v15-test-logs altındadır. Windows PowerShell 5.1 süreçleri ve gerçek WPF olayları kullanıldı. İlk testlerde yeni fonksiyonların eksikliği ve startup sekme sayısı hataları gözlendi; uygulamadan sonra geçti.

Fixture kapsamı: ledger/rapor tekrarını önleme; hedef başına tek sonuç; eski alanlar ve modül adlandırmalı raporlar; tarih/literal filtre/sayfa; eksik/bozuk ve başlık-only rapor; hedefsiz Error.csv; çalışma kimliği izolasyonu; bilinmeyen kod; belirsiz/reboot/erişim/yetki/son doğrulama; ZIP izin listesi, değişen kaynak, mevcut dosya üzerine yazmama, SHA-256 doğrulaması ve junction reddi. Gerçek WPF testleri boş ekran, seçim/yenileme/filtre, teşhise geçiş ve yanlış çalışma sonuçlarının gösterilmemesini sınar.

## İnceleme bulguları

Bağımsız salt okunur kod incelemesi yapıldı. Çalışma kimliğinin indeks ve ayrıntıda farklı filtrelenmesi ve keyfi CSV/HTML dosyalarının arşive girebilmesi Important olarak bulundu; regresyonlar eklenip düzeltildi. Global Error.csv ile boş rapor HTML erişimi de doğrulandı. Yalnızca bilinen üretici dosya adları ve izin verilen worker logları dışa aktarılır. Rapor dışı LogDestination izlenmez.

Tam turdaki NoUi testi yeni yönetici ekranındaki yerel MessageBox'ları uzak pencere gibi işaretledi. Mevcut App/PackageUi istisnası yalnızca yeni HistoryUi dosyasına genişletildi. Uzak paket worker'ının gerçek sahte-PsExec argüman testleri korunur ve geçti. Runner veya operasyon motoru değiştirilmedi.

## Görsel ve gerçek test ayrımı

screenshots-v15 görüntüleri gerçek WPF kontrollerinde yapay TEST/PC-TEST verileriyle üretilmiştir. Normal ve 1366x768/yüzde 125'e karşılık gelen küçük içerik alanı incelendi. Geçmişteki alt hedef/adım alanı kısa ekranda kaydırmayla erişilir; teşhis metni ayrıca kaydırılır.

Bu teslimde gerçek şirket hedefine bağlantı, paket kurulumu veya mutasyon çalıştırılmadı. v10/v11 canlı kayıtları tarihsel kanıttır. 50010 gerçek kök nedeni çözülmüş sayılmaz. Çok büyük arşivlerde ilk indeksleme dosya sayısına bağlıdır; uzak veri/merkezi geçmiş eklenmedi. Loglar otomatik sansürlenmez; tanı ZIP'i paylaşılmadan önce incelenir.

## Dağıtım

v14 ürün dosyaları korunur; v15 ayrı klasör ve bütünlüğü doğrulanmış ZIP olarak hazırlanır. Runtime ve APPDATA yolları değişmez. Drive yüklemesi kullanıcı isteğiyle yapılır; bu teslimde yükleme yapılmadı. Git deposu olmadığı için sibling kopya, hash ve test kayıtları kullanıldı.
