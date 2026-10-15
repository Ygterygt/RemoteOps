"""Package the validated v22 delivery; never overwrite an existing release ZIP."""
from pathlib import Path
import csv, hashlib, json, re, zipfile
from pypdf import PdfReader

root=Path(__file__).resolve().parents[2]
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def save(path,data): path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
assert load(root/'VERSION.json')['version']==22
tests=load(root/'docs/V22_TEST_SUMMARY.json')
assert tests['total']==76 and tests['passed']==76 and tests['failed']==0
parse=list(csv.DictReader((root/'docs/V22_PARSE_RESULTS.csv').open(encoding='utf-8-sig')))
assert all(int(r['Errors'])==0 for r in parse)
previous=root.parent/'YD_RemoteOps.App_v21'
old=load(previous/'docs/V21_VALIDATION.json')
assert all((previous/r['path']).is_file() and digest(previous/r['path'])==r['sha256'] for r in old['files'])
oldzip=root.parent/'YD_RemoteOps.App_v21.zip'
assert digest(oldzip)=='c830fc6b3245a2283a68453e10ed4e6dd662ae278f8819e434160318e77be58b'
for relative in ['RemoteOps.App/RemoteOps.Runner.ps1','RemoteOps.App/RemoteOps.Recovery.ps1','RemoteOps.App/RemoteOps.Deployment.ps1','RemoteOps.App/RemoteOps.RecipeExecution.ps1']:
 assert digest(root/relative)==digest(previous/relative)
assert all(digest(f)==digest(previous/f.relative_to(root)) for f in (root/'Modules').rglob('*') if f.is_file())
broken=[]
for doc in (root/'docs').glob('*.md'):
 for link in re.findall(r'\]\(([^)]+)\)',doc.read_text(encoding='utf-8-sig')):
  if ':' not in link and not link.startswith('#') and not (doc.parent/link.split('#')[0]).exists():broken.append([doc.name,link])
assert not broken,broken
pdfs=[]
for path in [root/'KULLANIM_KILAVUZU.pdf',*(root/'docs').glob('RemoteOps_*.pdf')]:
 reader=PdfReader(path);assert 'YD_RemoteOps.App_v22' in reader.pages[0].extract_text()
 pdfs.append(dict(file=path.relative_to(root).as_posix(),pages=len(reader.pages),bytes=path.stat().st_size,sha256=digest(path)))
historical=root/'docs/DOKUMAN_DOGRULAMA_v21_HISTORY.json'
if not historical.exists():historical.write_bytes((root/'docs/DOKUMAN_DOGRULAMA.json').read_bytes())
data=dict(date='2026-10-15',distribution=root.name,version=22,previousVersion=21,operator_model='single operator; multiple execution credentials retained',test_files=tests,powershell_parse=dict(files=len(parse),errors=0),pdfs=pdfs,ui_verification='Real WPF fixtures, 9 screens; diagnosis/recovery normal and 125 percent; 960x550 content; PDF contact sheets visually inspected.',remote_live_tests='Not performed. Local fixtures and mocked remote boundaries only.',code_review=dict(independent=True,remaining_blockers=0,resolved='Recovery refresh failure clears stale cards; failing/passing WPF regression and independent reproduction verified.'),preserved=dict(previous_source_manifest_files=len(old['files']),previous_source_unchanged=True,previous_zip_unchanged=True,remote_motor_and_modules_unchanged=True,runtime_root=r'C:\Temp\YD_RemoteOps.App',appdata_root=r'%APPDATA%\MDRemoteOps'),limits=['No current remote endpoint validation.','Recovery records do not prove current live target state.','Small windows require scrolling.','Earlier screenshots retained as historical documentation.'],broken_document_links=broken,drive_upload='Not requested; not performed.')
save(root/'docs/V22_VALIDATION.json',data)
save(root/'docs/DOKUMAN_DOGRULAMA.json',data)
files=[f for f in root.rglob('*') if f.is_file()]
archive=root.parent/(root.name+'.zip')
if archive.exists():raise FileExistsError(archive)
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for f in sorted(files):z.write(f,root.name+'/'+f.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 assert len(z.namelist())==len(files)
 for f in files:
  assert hashlib.sha256(z.read(root.name+'/'+f.relative_to(root).as_posix())).hexdigest()==digest(f)
verification=dict(distribution=root.name,zip=str(archive),bytes=archive.stat().st_size,sha256=digest(archive),verified_entries=len(files),crc='PASS',all_file_hashes='PASS',test_files='76/76',powershell_parse=f'{len(parse)} files, 0 errors',previous_zip_unchanged=True,previous_source_unchanged=True,drive_upload=False)
save(root.parent/(root.name+'.verification.json'),verification)
print(json.dumps(verification,indent=2))
