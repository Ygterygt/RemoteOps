from pathlib import Path
import csv, hashlib, html, json, shutil

root=Path(__file__).resolve().parents[2]
docs=root/'docs'
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
summary=load(docs/'v27-offline-acceptance/acceptance-02/summary.json')
assert summary['Total']==17 and summary['Passed']==17 and summary['Failed']==0 and summary['UnexpectedBoundaryBlocks']==0
review=load(docs/'V27_INDEPENDENT_REVIEW.json')
reg=list(csv.DictReader((docs/'V27_SAFE_REGRESSION.csv').open(encoding='utf-8-sig')))
assert len(reg)==12 and all(x['ExitCode']=='0' for x in reg)
baseline=root.parent/'YD_RemoteOps.App_v26'
files={p.relative_to(root).as_posix():p for d in ['RemoteOps.App','Modules'] for p in (root/d).rglob('*') if p.is_file()}
old={p.relative_to(baseline).as_posix():p for d in ['RemoteOps.App','Modules'] for p in (baseline/d).rglob('*') if p.is_file()}
assert files.keys()==old.keys()
identity=[dict(file=k,sha256=sha(p),v26_sha256=sha(old[k]),same=sha(p)==sha(old[k])) for k,p in files.items()]
assert all(x['same'] for x in identity)
assert sha(root.parent/'YD_RemoteOps.App_v26.zip')=='829994a4ec850320e405d867e42e2687e5ef586e4e92af9372d55d9b6e2fec3e'
save(docs/'V26_CODE_IDENTITY.json',dict(subject_version=26,delivery_version=27,files=len(identity),all_equal=True,records=identity))
model=load(docs/'V27_MODEL_SELFTEST.json');assert model['Status']=='PASS' and model['Blocked']==5
model_dir=docs/'v27-model-evidence';model_dir.mkdir(exist_ok=True)
for name in ['state.json','state.json.blocked.jsonl']:
 shutil.copy2(Path(model['FixtureRoot'])/name,model_dir/name)
titles=[
 'Koşul, servis başlatma, yeni durumu okuma, durdurma, başlangıç türü ve listeleme',
 'Üç hedefte eşleşen, eşleşmeyen ve eksik registry değeri',
 'Sayı ve metin registry türlerinde otomatik karşılaştırma',
 'Eksik registry değerinin Eşit değil koşulunu sağlamaması',
 'Tümü seçeneğinde bir yanlış kontrolün işlemi engellemesi',
 'Herhangi biri seçeneğinde tek doğru kontrolün yeterli olması',
 'Herhangi biri doğru olsa da okuma hatasının işlemi durdurması',
 'Koşul sağlanmazsa durdur; sonraki hedefin bağımsız devam etmesi',
 'İşlem hatasında hedefin kalan adımlarının başlamaması',
 'Yeniden başlatmada durdur, durmuş durumu gözle, başlat sırası',
 'İlk değişiklikten sonra iptal; yeni adım/hedefte değişiklik yapılmaması',
 'Eski ortak koşulun bir kez değerlendirilmesi ve kapsamının korunması',
 'Eksik onay, değişmiş önizleme ve önizlemeden vazgeçmede iş başlamaması',
 'Yanıltıcı başarı ve yanlış hedef kanıtının bağımsız kontrolle reddedilmesi',
 'Başlangıç türü değişikliğinin sonraki koşulda okunması',
 'Registry anahtarı ve servis varlığına göre doğru hedef seçimi',
 'Bozuk gerçek sayısal registry verisinin hata sayılması',
]
worker_count=sum(len(set(r['WorkerPids'])-{r['CoordinatorPid']}) for r in summary['Runs'])
record=dict(subject_version=26,delivery_version=27,operational_scenarios=dict(total=17,passed=17,failed=0),safe_regression_files=dict(total=12,passed=12),model_guard_negative_checks=5,independent_run_artifacts=len(summary['Runs']),independent_negative_controls=2,real_coordinator_processes=len(summary['Runs']),real_child_processes=worker_count,seconds=summary['Seconds'],sampled_combined_working_set_mib=summary['SampledPeakCombinedWorkingSetMiB'],unexpected_boundary_blocks=0,source_code=dict(files=len(identity),same_as_v26=True),live_targets=False,transport_verified=False,evidence='v27-offline-acceptance/acceptance-02/summary.json')
save(docs/'V27_TEST_SUMMARY.json',record)
scope='''Gerçek WPF denetimleriyle Adım ekle, işlem ve koşul alanları, otomatik ad, kaydetme, katalogdan yeniden açma, önizleme ve RECETE onayı kullanıldı. Gerçek Start-RemoteOpsRequest istek oluşturdu; gerçek koordinatör ve ayrı PowerShell çocuk süreçleri çalıştı. Gerçek servis operasyon modülü, koşul karşılaştırma/karar kodu ve raporlama kullanıldı. Yalnızca geçici kopyada uzak erişim sınırları ve çocuk süreç başlatma bağları yerel modele yönlendirildi. Üretim kodu değiştirilmedi.'''
limits='''Gerçek registry sağlayıcısından okuma ve tür çözümleme, CIM/DCOM/SMB/PsExec bağlantısı, domain hesabı/parola, güvenlik duvarı veya EDR davranışı sınanmadı. Dosya/paket işlemleri bu kabul matrisine dahil değildir. WPF denetim olayları programla tetiklendi; fare/klavye erişilebilirlik testi değildir. İptalde gerçek iptal dosyası mekanizması kullanıldı; Durdur düğmesinin onay iletişim kutusu otomatik tıklanmadı. Fonksiyon engelleri işletim sistemi düzeyinde ağ güvenlik duvarı veya ağ trafiği kaydı değildir. Bellek değeri örneklenmiş çalışma belleğidir; kesin üst sınır değildir.'''
lines=['# v26 reçete ve koşul akışı - hafif kabul testi','',f"Sonuç: **17/17 operasyon senaryosu geçti.** Ek olarak 12/12 güvenli yerel regresyon dosyası ve 5/5 model sınırı negatif kontrolü geçti. Bağımsız inceleme {len(summary['Runs'])} çalışma kaydını doğruladı.",'',f"Uygulama kodunun {len(identity)} dosyası v26 ile birebir aynıdır. v27 yalnızca test araçları ve doğrulama teslimidir. Sanal makine kullanılmadı. Kabul koşusu {summary['Seconds']:.2f} saniye sürdü; örneklenen toplam çalışma belleği {summary['SampledPeakCombinedWorkingSetMiB']:.1f} MiB oldu.",'','## Nasıl test edildi','',scope,'','## Senaryolar','', '| No | Senaryo | Sonuç |','|---|---|---|']
rows=[]
for i,(case,title) in enumerate(zip(summary['Cases'],titles),1):
 assert case['Status']=='PASS'
 lines.append(f'| {i} | {title} | Geçti |')
 path='v27-offline-acceptance/acceptance-02/'+case['Id']+'/report/Results.html'
 link=f'<a href="{html.escape(path)}">İşlem raporu</a>' if (docs/path).exists() else 'İş başlatılmadığı doğrulandı'
 rows.append(f'<tr><td>{i}</td><td>{html.escape(title)}</td><td class="pass">Geçti</td><td>{link}</td></tr>')
lines+=['','## Yanıltıcı başarı kontrolü','','14. senaryoda model bilerek başarılı dönüş kodu verdi fakat servis durumunu değiştirmedi. Gerçek çalıştırıcı Success satırı üretti. Kabul doğrulayıcısı gerçek son durum bekleneni karşılamadığı için bu kanıtı reddetti. Ayrıca kopyalanmış kanıtta yanlış hedef kimliği de reddedildi. Bu negatif kontrolün geçmesi, yanıltıcı başarının yakalandığı anlamına gelir.','','## Bağımsız kanıt kontrolü','',f'{len(summary["Runs"])} çalışmanın CSV, ledger ve terminal checkpoint kayıtları bağımsız olarak okundu. İlk zincirin servis başlatmadan sonra yeni durumu okuduğu, yeniden başlatmanın Stop ile Start arasında Stopped durumunu gözlemlediği doğrulandı. İki bozulmuş gerçek zincir kanıtı reddedildi. Ayrıntılar V27_INDEPENDENT_REVIEW.json içindedir.','','## Kapsam dışında kalanlar','',limits,'','## Tekrar çalıştırma','','Kökte HAFIF_TEST_CALISTIR.bat dosyasını açın. Yönetici yetkisi veya sanal makine kurulumu gerekmez. Sonuçlar docs/v27-offline-acceptance altında yeni tarihli klasöre yazılır. Uygulamanın kişisel katalog/profil ve gerçek çalışma yolları testte kullanılmaz; geçici dizine yönlendirilir.','','Bu teslimin kabul sonucu acceptance-02 klasöründedir. Ön geliştirme koşularında test aracının dosya paylaşımı okuma yarışı giderildi; bu denemeler ayrı klasörlerde tutulmuştur. Üretim kodunda düzeltme yapılmadı.','']
(docs/'V27_HAFIF_TEST_RAPORU.md').write_text('\n'.join(lines),encoding='utf-8-sig')
body=f'''<!doctype html><html lang="tr"><meta charset="utf-8"><title>v26 Hafif Kabul Testi</title><style>body{{font:16px Segoe UI,Arial;background:#edf2f6;color:#1f3342;margin:0}}main{{max-width:1050px;margin:30px auto;padding:28px;background:white;border-radius:16px}}h1{{font-size:30px}}.hero{{background:#e4f4ed;padding:18px;border-radius:12px}}table{{border-collapse:collapse;width:100%;font-size:14px}}td,th{{padding:12px;border-bottom:1px solid #dbe3ea;text-align:left}}th{{background:#edf2f6}}.pass{{color:#087145;font-weight:bold}}p{{line-height:1.65}}a{{color:#075a99}}</style><main><h1>v26 reçete ve koşul akışı</h1><div class="hero"><b>17 / 17 operasyon senaryosu geçti</b><p>12 / 12 güvenli regresyon dosyası · 5 / 5 sınır negatif kontrolü<br>{len(summary['Runs'])} gerçek koordinatör · {worker_count} çocuk süreç · {summary['Seconds']:.2f} saniye<br>Örneklenen toplam çalışma belleği: {summary['SampledPeakCombinedWorkingSetMiB']:.1f} MiB · Sanal makine yok</p></div><p>v26 uygulama kodunun {len(identity)} dosyası aynı kaldı. v27 test araçları ve doğrulama teslimidir. Canlı hedeflerde çalışma yapılmadı.</p><h2>Gerçek akış</h2><p>{html.escape(scope)}</p><h2>Sonuçlar</h2><table><tr><th>No</th><th>Senaryo</th><th>Sonuç</th><th>Kanıt</th></tr>{''.join(rows)}</table><h2>Başarı raporuna tek başına güvenilmedi</h2><p>14. senaryoda başarılı dönüş kodu ve gerçek Success raporu üretildiği halde hedef durumunu değiştirmeyen model kullanıldı. Bağımsız kabul kontrolü bu sonucu reddetti. Yanlış hedef olarak değiştirilmiş kanıt da reddedildi.</p><h2>Bağımsız inceleme</h2><p>CSV, ledger ve terminal checkpoint kayıtları ayrıca kontrol edildi. Yeni servis durumunun sonraki koşulda okunması ve yeniden başlatma sırası doğrulandı. <a href="V27_INDEPENDENT_REVIEW.json">İnceleme kaydı</a> · <a href="V26_CODE_IDENTITY.json">v26 kod eşitliği</a> · <a href="V27_TEST_SUMMARY.json">Özet kayıt</a></p><h2>Doğrulamanın sınırları</h2><p>{html.escape(limits)}</p><h2>Tekrar çalıştırma</h2><p>Kökteki <b>HAFIF_TEST_CALISTIR.bat</b> dosyasını açın. Yeni sonuçlar tarihli bir klasöre kaydedilir. Bu teslimin kabul kaydı acceptance-02 klasöründedir; önceki geliştirme denemeleri ayrı tutulmuştur.</p></main></html>'''
(docs/'V27_HAFIF_TEST_RAPORU.html').write_text(body,encoding='utf-8')
section='''
15 Ekim 2026 · YD_RemoteOps.App_v27

## v27 - v26 kodu için hafif operasyon kabul testi

Bu teslim uygulama davranışını değiştirmez. RemoteOps.App ve Modules içindeki 36 üretim dosyası v26 ile birebir aynıdır. v26 kaynak ve ZIP korunmuştur. Yeni teslim hafif test araçları, kayıtlar ve kabul raporunu ekler.

Gerçek WPF reçete oluşturma, otomatik ad, adım içi koşul, kaydetme/yeniden açma, önizleme ve RECETE onayı; gerçek koordinatör ve çocuk süreçleriyle sınandı. Uzak erişim sınırında yerel, durumu değişen servis/registry modeli kullanıldı. 17/17 operasyon senaryosu, 12/12 yerel regresyon dosyası ve 5/5 sınır negatif kontrolü geçti. Bağımsız inceleme 16 çalışma kaydını doğruladı. Çalışma yaklaşık 149 saniye sürdü; gözlenen toplam çalışma belleği yaklaşık 700 MiB idi. Sanal makine kullanılmadı.

Yanıltıcı Success raporu hedef durumuyla ayrıca karşılaştırıldı ve reddedildi. Koşul atlama/durdurma, All/Any, okuma/işlem hatası, iptal, hedef bağımsızlığı ve eski ortak koşul davranışı doğrulandı. Gerçek ağ/Windows sağlayıcısı, domain hesabı, SMB/PsExec ve EDR testi yapılmadı. Durdur onay kutusu yerine aynı gerçek iptal isteği mekanizması çağrıldı.

[Ayrıntılı kabul raporu](V27_HAFIF_TEST_RAPORU.html) · [Kod eşitliği](V26_CODE_IDENTITY.json)

Tekrar çalıştırmak için kökte HAFIF_TEST_CALISTIR.bat dosyasını açın. Çıktılar yeni tarihli klasöre yazılır. Kişisel veri yolları testte geçici dizine yönlendirilir; gerçek uygulamanın C:\\Temp\\YD_RemoteOps.App ve AppData yolları değişmez.

## v26 arayüzü ve önceki teslimlerin referansı

Aşağıdaki ekran görüntüleri ve v26 açıklamaları aynı kalan uygulama arayüzünün referansıdır. v27 yalnızca test teslimidir.

'''
for name in ['KULLANIM_KILAVUZU.md','TEKNIK_EL_KITABI.md','CALISMA_MANTIGI.md','INCELEME_RAPORU.md','GELECEK_OPERASYON_OLUSTUR.md']:
 p=docs/name;s=p.read_text(encoding='utf-8-sig');title,rest=s.split('\n',1)
 if '## v27 -' not in s:p.write_text(title+'\n'+section+rest,encoding='utf-8-sig')
p=docs/'tools/build_documents.py';p.write_text(p.read_text(encoding='utf-8-sig').replace('YD_RemoteOps.App_v26','YD_RemoteOps.App_v27'),encoding='utf-8')
print(json.dumps(record,ensure_ascii=False,indent=2))
