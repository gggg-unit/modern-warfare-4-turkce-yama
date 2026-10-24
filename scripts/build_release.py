"""Build the offline release ZIP from the verified patch files."""
import argparse,hashlib,json,pathlib,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def build(payload,output):
 manifest=json.loads((ROOT/'metadata/release-manifest.json').read_text(encoding='utf-8-sig'))
 for row in manifest['files']:
  p=payload/row['path']
  if not p.is_file() or sha(p)!=row['sha256']:raise ValueError('Payload mismatch: '+row['path'])
 output.mkdir(parents=True,exist_ok=True)
 path=output/('Modern-Warfare-4-Turkce-Yama-v'+manifest['version']+'.zip')
 with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for row in manifest['files']:z.write(payload/row['path'],'dosyalar/'+row['path'])
  for p in sorted((ROOT/'installer').iterdir()):
   if p.is_file():z.write(p,p.name)
  for name in ['README.md','LICENSE']:z.write(ROOT/name,name)
  z.writestr('dosyalar.json',json.dumps(manifest,ensure_ascii=False,indent=2))
 with zipfile.ZipFile(path) as z:
  assert z.testzip() is None
  for row in manifest['files']:assert hashlib.sha256(z.read('dosyalar/'+row['path'])).hexdigest().upper()==row['sha256']
 print(json.dumps({'file':str(path),'sha256':sha(path),'bytes':path.stat().st_size}))
 return path
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--payload',required=True,type=pathlib.Path);ap.add_argument('--output',type=pathlib.Path,default=ROOT/'dist');a=ap.parse_args();build(a.payload,a.output)
