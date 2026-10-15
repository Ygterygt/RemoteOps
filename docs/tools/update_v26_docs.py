from pathlib import Path

root=Path(__file__).resolve().parents[2]
common='''
15 Ekim 2026 · YD_RemoteOps.App_v26

## v26 - Adımın içinde koşul ve otomatik adlandırma

Reçete ekranı adım listesine odaklanır. İşlem alanlarını doldurmak için Adım ekle veya seçili adımı düzenleme komutunu kullanın. Düzenleme ayrı pencerede açılır; işlem bilgileri ve çalışma koşulu ayrı bölümlerde tutulur. Ana sayfada aşağı kaydırarak alan aramak gerekmez. Uzun listeler kendi alanında kaydırılabilir.

Adım adına ayrıca metin yazmak gerekmez. İşlem ve ilgili servis, dosya veya registry bilgileri adı oluşturur. Örneğin Servisi başlat · Spooler. İsterseniz adı özelleştirebilirsiniz; eski reçetelerde verdiğiniz özel adlar korunur.

İlgili adımın çalışma koşulunda servis veya registry kontrolü tanımlayın. Registry değerinde tür seçilmez: 1 veya 16.0.444 gibi beklenen değeri girin. Gerçek hedef türüne göre karşılaştırma yapılır. Servis koşulunda yalnızca servisle ilgili alanlar görünür. Birden fazla kontrol için Tümü / Herhangi biri davranışı korunur. Koşul sağlanmazsa adımı atlama veya hedefin reçetesini durdurma seçilebilir.

Mevcut ortak koşulların bağlı adımları ve tek kez değerlendirilme davranışı korunur. Eski ortak koşul değiştirilirse aynı koşula bağlı bütün adımları etkiler; düzenleyici bu kapsamı belirtir. Yeni koşullar ilgili işlemle birlikte yönetilir. Uyumsuz sıra değişiklikleri engellenir. Düzenlemeden vazgeçmek kayıtlı reçeteyi veya taslağı değiştirmez.

Hedefler ayrı bölümde yönetilir; ortak hedef araçları korunur. Reçeteyi kaydetmek hedefte işlem başlatmaz. Kaydedilmiş reçetenin önizlemesi ve RECETE çalıştırma onayı devam eder. Gerçek uzak hedef testi bu teslimde yapılmamıştır.

![v26 reçete ekranı](screenshots-v26/recete-ana.png)

![Adımın çalışma koşulu](screenshots-v26/adim-kosulu.png)

## Önceki sürümlerin tarihsel açıklamaları

Aşağıdaki v25 ve daha eski bölümler kendi teslimlerini anlatır. Güncel v26 kullanımında üstteki adım düzenleme akışı geçerlidir.

'''
for name in ['KULLANIM_KILAVUZU.md','TEKNIK_EL_KITABI.md','CALISMA_MANTIGI.md','INCELEME_RAPORU.md','GELECEK_OPERASYON_OLUSTUR.md']:
    p=root/'docs'/name
    text=p.read_text(encoding='utf-8-sig')
    title,body=text.split('\n',1)
    if '## v26 -' not in text:p.write_text(title+'\n'+common+body,encoding='utf-8-sig')
p=root/'docs/tools/build_documents.py'
p.write_text(p.read_text(encoding='utf-8-sig').replace('YD_RemoteOps.App_v25','YD_RemoteOps.App_v26'),encoding='utf-8')
p=root/'RemoteOps.App/README.md'
text=p.read_text(encoding='utf-8-sig').replace('# YD RemoteOps v25','# YD RemoteOps v26').replace('[v25 doğrulama](../docs/V22_INCELEME.md)','[v26 doğrulama](../docs/V26_INCELEME.md)')
text+='\n## v26 reçete düzenleyicisi\n\nKoşullar ilgili adımın içinde düzenlenir. Adım adları otomatik oluşur; mevcut özel adlar korunur. Ana sayfa sabit komut alanı ve esneyen liste kullanır. İşlem ve koşul ayrı düzenleme penceresindedir. Önceki sürümlere ait aşağıdaki kullanım açıklamaları tarihseldir.\n'
p.write_text(text,encoding='utf-8-sig')
