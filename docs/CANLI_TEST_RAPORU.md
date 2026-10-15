# v10 yerel canlı test raporu

14 Ekim 2026 · Mevcut Windows bilgisayarı · Gerçek CIM/DCOM ve SMB çağrıları

Son turda 18/18 senaryo PASS. `RemoteCallsMocked=false`; yalnızca raporların otomatik açılması bastırıldı. Menü cevapları GUI Runner ile aynı yöntemle kuyruktan verildi. Testler yönetici token ile çalıştı.

| Senaryo | Sonuç | Süre (sn) |
| --- | --- | --- |
| Transport.CIM-DCOM | PASS | 0.33 |
| Transport.AdminShare | PASS | 0.02 |
| File.Pull | PASS | 0.24 |
| File.Push | PASS | 0.07 |
| File.Compare | PASS | 0.13 |
| File.BackupDeleteRestore | PASS | 0.43 |
| File.BrowsePull | PASS | 0.05 |
| File.BrowseMoveRollback | PASS | 0.09 |
| File.BrowseReplaceRollback | PASS | 0.07 |
| Registry.CreateOwnedFixture | PASS | 0.01 |
| Registry.ReadEditRollback | PASS | 0.26 |
| Registry.DeleteRollback | PASS | 0.09 |
| Service.CreateOwnedFixture | PASS | 0.24 |
| Service.ListStartRestartStop | PASS | 11.93 |
| Service.StartupRollback | PASS | 1.26 |
| Task.CreateOwnedFixture | PASS | 0.38 |
| Task.ListDisableEnableRunDeleteRollback | PASS | 9.42 |
| Process.QueryKillOwnedPID | PASS | 0.67 |

## Kapsam ve temizlik

Benzersiz GUID altında ProgramData test klasörü ve HKLM alt anahtarı, tek LocalService test servisi, LocalService ile yalnızca `cmd /c exit 0` çalıştıran görev ve kendimize ait bekleyen süreç kullanıldı. Mevcut kullanıcı dosyaları/registry değerleri, kurulu servisler ve görevler değiştirilmedi. Test süreci yalnızca kaydedilen kendi PID değeriyle sonlandırıldı.

- OwnedProcessExited: true
- TaskFolderAbsent: true
- SandboxAbsent: true
- RegistryAbsent: true
- ServiceAbsent: true
- TaskAbsent: true

CleanupErrors boş. GUID klasörü, registry alt anahtarı, test servisi, görev, görev klasörü ve yardımcı süreç kaldırıldı. İlk turdan kalan boş test registry üst anahtarı da boşluk kontrolüyle temizlendi.

## İlk turda bulunan ve düzeltilen sorunlar

1. Türkçe kültürde büyük/küçük harf duyarsız ASCII regex kontrolü, `I` içeren gerçek GUI çalışma kimliklerini ve istemci adlarını reddediyordu. Açık `[A-Za-z]` aralığı kullanılan ad kontrolleri `-cnotmatch` ile kültür etkisinden ayrıldı; GUI-RUN ve YIGIT örnekleri regresyon testlerine eklendi. Bu düzeltme log gruplaması ve log temizleme kullanıcı adı doğrulamasını da kapsar.
2. DCOM CimSession ile görev silerken `-Confirm:$false` bağlamak desteklenmiyordu. Kullanıcı onayı, XML yedeği ve manifest korundu; silme çağrısında açık Confirm parametresi kaldırıldı ve ConfirmPreference yalnızca alt kapsamda None yapıldı.
3. Test düzeneğinin registry temizliğinde provider hatası görülmesine rağmen yaprak kayıt silinmişti. Kesin test anahtarları için .NET registry API ile temizleme ve boş üst anahtar kontrolü kullanıldı; ikinci turda temizlik hatası kalmadı.

İlk başarısız turun kaydı `live-test/first-run` altında saklanır; nihai sonuçlar `live-test/LOCAL_LIVE_TEST.json` ve `.csv` dosyalarıdır. Bunlar şirket ağı, başka Windows sürümleri veya gerçek dağıtım paketleri için kabul testi yerine geçmez.
