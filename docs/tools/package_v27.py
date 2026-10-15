from pathlib import Path
import csv, hashlib, json, re, zipfile
from pypdf import PdfReader
root=Path(__file__).resolve().parents[2]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
assert load(root/'VERSION.json')['version']==27
summary=load(root/'docs/V27_TEST_SUMMARY.json')
assert summary['operational_scenarios']==dict(total=17,passed=17,failed=0)
assert summary['safe_regression_files']==dict(total=12,passed=12)
assert summary['unexpected_boundary_blocks']==0
assert load(root/'docs/V27_INDEPENDENT_REVIEW.json')['Status']=='PASS'
identity=load(root/'docs/V26_CODE_IDENTITY.json')
previous=root.parent/'YD_RemoteOps.App_v26';previous_zip=root.parent/'YD_RemoteOps.App_v26.zip'
assert digest(previous_zip)=='829994a4ec850320e405d867e42e2687e5ef586e4e92af9372d55d9b6e2fec3e'
current={p.relative_to(root).as_posix():p for name in ['RemoteOps.App','Modules'] for p in (root/name).rglob('*') if p.is_file()}
baseline={p.relative_to(previous).as_posix():p for name in ['RemoteOps.App','Modules'] for p in (previous/name).rglob('*') if p.is_file()}
assert current.keys()==baseline.keys() and len(current)==identity['files']==36
for name,p in current.items():assert digest(p)==digest(baseline[name])
with zipfile.ZipFile(previous_zip) as z:
 for name in z.namelist():
  if name.endswith('/'):continue
  p=previous/Path(name).relative_to(previous.name)
  assert p.is_file() and hashlib.sha256(z.read(name)).hexdigest()==digest(p)
 old_count=len(z.namelist())
parse=list(csv.DictReader((root/'docs/V27_PARSE_RESULTS.csv').open(encoding='utf-8-sig')))
assert parse and all(r['Errors']=='0' for r in parse)
broken=[]
for p in (root/'docs').glob('*.md'):
 for ref in re.findall(r'\]\(([^)]+)\)',p.read_text(encoding='utf-8-sig')):
  if ':' not in ref and not ref.startswith('#') and not (p.parent/ref.split('#')[0]).exists():broken.append([p.name,ref])
assert not broken,broken
pdfs=[]
for p in [root/'KULLANIM_KILAVUZU.pdf',*(root/'docs').glob('RemoteOps_*.pdf')]:
 reader=PdfReader(p);assert 'YD_RemoteOps.App_v27' in reader.pages[0].extract_text()
 pdfs.append(dict(file=p.relative_to(root).as_posix(),sha256=digest(p),pages=len(reader.pages)))
history=root/'docs/DOKUMAN_DOGRULAMA_v26_HISTORY.json'
if not history.exists():history.write_bytes((root/'docs/DOKUMAN_DOGRULAMA.json').read_bytes())
validation=dict(distribution=root.name,version=27,subject_code_version=26,date='2026-10-15',type='Test-only delivery; production files unchanged',test_summary=summary,powershell_parse=dict(files=len(parse),errors=0),pdfs=pdfs,previous_source_files_unchanged=old_count,previous_zip_unchanged=True,source_file_set_and_hashes_equal=True,ui_images='v26 reference screenshots; unchanged application UI',live_targets=False,transport_verified=False,broken_document_links=broken,drive_upload=False)
save(root/'docs/V27_VALIDATION.json',validation);save(root/'docs/DOKUMAN_DOGRULAMA.json',validation)
paths=sorted(p for p in root.rglob('*') if p.is_file())
archive=root.parent/(root.name+'.zip')
if archive.exists():raise FileExistsError(archive)
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in paths:z.write(p,root.name+'/'+p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None and len(z.namelist())==len(paths)
 for p in paths:assert hashlib.sha256(z.read(root.name+'/'+p.relative_to(root).as_posix())).hexdigest()==digest(p)
record=dict(zip=str(archive),bytes=archive.stat().st_size,sha256=digest(archive),verified_entries=len(paths),crc='PASS',all_file_hashes='PASS',operational_scenarios='17/17',regression_files='12/12',production_same_as_v26=True,previous_release_unchanged=True,live_targets=False,drive_upload=False)
save(root.parent/(root.name+'.verification.json'),record)
print(json.dumps(record,indent=2))
