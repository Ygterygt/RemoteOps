"""Create v24 only after validation. Preserve and compare the previous release."""
from pathlib import Path
import csv,hashlib,json,re,zipfile
from pypdf import PdfReader
root=Path(__file__).resolve().parents[2]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
assert load(root/'VERSION.json')['version']==24
tests=load(root/'docs/V24_TEST_SUMMARY.json')
assert tests['total']==81 and tests['passed']==81 and tests['failed']==0
results=list(csv.DictReader((root/'docs/V24_TEST_RESULTS.csv').open(encoding='utf-8-sig')))
assert len(results)==81 and all(r['ExitCode']=='0' for r in results)
parse=list(csv.DictReader((root/'docs/V24_PARSE_RESULTS.csv').open(encoding='utf-8-sig')))
assert all(int(r['Errors'])==0 for r in parse)
previous=root.parent/'YD_RemoteOps.App_v23';oldzip=root.parent/'YD_RemoteOps.App_v23.zip'
assert digest(oldzip)=='13faef82be58cf08a50942413100e3da3b139c9be430bdf1abbdb241b22e4fac'
with zipfile.ZipFile(oldzip) as z:
 for name in z.namelist():
  if name.endswith('/'):continue
  f=previous/Path(name).relative_to(previous.name)
  assert f.is_file() and hashlib.sha256(z.read(name)).hexdigest()==digest(f),str(f)
 oldcount=len(z.namelist())
for f in (root/'Modules').rglob('*'):
 if f.is_file():assert digest(f)==digest(previous/f.relative_to(root))
for name in ['RemoteOps.Deployment.ps1','RemoteOps.Recovery.ps1','RemoteOps.WorkflowUi.ps1','RemoteOps.TargetGroups.ps1']:
 assert digest(root/'RemoteOps.App'/name)==digest(previous/'RemoteOps.App'/name)
broken=[]
for doc in (root/'docs').glob('*.md'):
 for link in re.findall(r'\]\(([^)]+)\)',doc.read_text(encoding='utf-8-sig')):
  if ':' not in link and not link.startswith('#') and not (doc.parent/link.split('#')[0]).exists():broken.append([doc.name,link])
assert not broken,broken
pdfs=[]
for p in [root/'KULLANIM_KILAVUZU.pdf',*(root/'docs').glob('RemoteOps_*.pdf')]:
 reader=PdfReader(p);assert 'YD_RemoteOps.App_v24' in reader.pages[0].extract_text()
 pdfs.append(dict(file=p.relative_to(root).as_posix(),pages=len(reader.pages),bytes=p.stat().st_size,sha256=digest(p)))
historical=root/'docs/DOKUMAN_DOGRULAMA_v23_HISTORY.json'
if not historical.exists():historical.write_bytes((root/'docs/DOKUMAN_DOGRULAMA.json').read_bytes())
validation=dict(date='2026-10-15',distribution=root.name,version=24,previousVersion=23,operator_model='single operator; existing execution accounts retained',test_files=tests,powershell_parse=dict(files=len(parse),errors=0),pdfs=pdfs,ui_verification='Real WPF condition groups, bound action, service/registry editor and saved preview; normal and 125 percent. All five updated PDF sections rendered and visually inspected.',code_review=dict(independent=True,remaining_blockers=0,resolved='Strict read-only provider validation and approved-check evidence matching; false skip/stop and All/Any error dominance verified; independent real isolated runner tests passed.'),preserved=dict(previous_source_files=oldcount,previous_source_unchanged=True,previous_zip_unchanged=True,nonrecipe_remote_modules_unchanged=True,runtime_root=r'C:\Temp\YD_RemoteOps.App',appdata_root=r'%APPDATA%\MDRemoteOps'),remote_live_tests='Not performed. Local fixtures and mocked remote boundaries only.',limits=['Recipe/1 behavior preserved; conditional Recipe/2 requires v24.','20 total steps including condition groups, 10 checks per group, one level and contiguous bound actions.','Checks and mutations are not atomic; no automatic rollback.','HKCU uses existing single interactive SID resolution; REG_EXPAND_SZ retains existing Remote Registry transport requirements.','No live endpoint acceptance tests.'],broken_document_links=broken,drive_upload='Not requested; not performed.')
save(root/'docs/V24_VALIDATION.json',validation);save(root/'docs/DOKUMAN_DOGRULAMA.json',validation)
files=sorted(p for p in root.rglob('*') if p.is_file())
archive=root.parent/(root.name+'.zip')
if archive.exists():raise FileExistsError(archive)
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in files:z.write(p,root.name+'/'+p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None and len(z.namelist())==len(files)
 for p in files:assert hashlib.sha256(z.read(root.name+'/'+p.relative_to(root).as_posix())).hexdigest()==digest(p)
record=dict(distribution=root.name,zip=str(archive),bytes=archive.stat().st_size,sha256=digest(archive),verified_entries=len(files),crc='PASS',all_file_hashes='PASS',test_files='81/81',powershell_parse=f'{len(parse)} files, 0 errors',previous_zip_unchanged=True,previous_source_unchanged=True,drive_upload=False)
save(root.parent/(root.name+'.verification.json'),record)
print(json.dumps(record,indent=2))
