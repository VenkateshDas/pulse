#!/usr/bin/env python3
"""Exercise CLI JSON, gating, fixture-only Trash moves and undo. Run via make cli-smoke."""
import subprocess,json,time,tempfile,pathlib,uuid,shutil,plistlib
binary=str(pathlib.Path(__file__).resolve().parents[1] / 'dist/cli/pulse')

def run(args,expected=0,timeout=120):
 t=time.monotonic(); p=subprocess.run([binary,*args,'--json'],capture_output=True,text=True,timeout=timeout)
 try: data=json.loads(p.stdout)
 except Exception: raise RuntimeError(f'{args[0]} invalid JSON: {p.stdout[:120]} {p.stderr[:120]}')
 assert p.returncode==expected,(args,p.returncode,data)
 print(args[0], 'exit',p.returncode, 'seconds',round(time.monotonic()-t,2),flush=True)
 return data
help=run(['--help']); assert len(help['subcommands'])==15
for command in help['subcommands']:
 run([command,'--help']); run([command,'--unknown'],2)
for args in [['clean','--yes'],['display','set','nan'],['procs','--limit','-1'],['vitals','--json=false']]:run(args,2)
root=pathlib.Path(tempfile.mkdtemp(prefix='pulse-cli-fixture-'))
try:
 (root/'one').write_bytes(b'pulse test'*2000);(root/'two').write_bytes((root/'one').read_bytes())
 data=run(['duplicates',str(root),'--min-size-mb','0.001']);assert data['duplicateGroupsCount']==1
 data=run(['duplicates',str(root),'--min-size-mb','1']);assert data['duplicateGroupsCount']==0
 run(['verdict',str(root)])
 # Whole-volume growth is intentionally excluded from this bounded fixture check.
 cache=pathlib.Path.home()/'Library/Caches'/('com.pulse.cli-fixture.'+str(uuid.uuid4()))
 cache.mkdir(); (cache/'fixture').write_text('pulse safe fixture')
 try:
  scan=run(['clean','--scan']);assert any(x['id']==str(cache) for x in scan)
  preview=run(['clean','--target',str(cache)]);assert preview['dryRun'] and cache.exists()
  preview=run(['clean','--target',str(cache),'--dry-run','--yes']);assert preview['dryRun'] and cache.exists()
  with (cache/'fixture').open() as opened:
   refused=run(['clean','--target',str(cache),'--yes'],1);assert refused['failures'] and cache.exists()
  result=run(['clean','--target',str(cache),'--yes']);assert not cache.exists() and len(result['undoIDs'])==1
  cache.mkdir();(cache/'conflict').write_text('keep')
  conflict=run(['undo','restore',result['undoIDs'][0]],1);assert conflict['remainingItems']==1 and (cache/'conflict').read_text()=='keep'
  # Only this generated conflicting fixture is removed; no user files are touched.
  (cache/'conflict').unlink();cache.rmdir()
  run(['undo','restore',result['undoIDs'][0]]);assert (cache/'fixture').read_text()=='pulse safe fixture'
 finally: shutil.rmtree(cache,ignore_errors=True)
 app=pathlib.Path.home()/'Applications'/('PulseCLIFixture-'+str(uuid.uuid4())+'.app')
 (app/'Contents').mkdir(parents=True)
 with (app/'Contents/Info.plist').open('wb') as f:plistlib.dump({'CFBundleIdentifier':'com.pulse.cli.fixture.'+str(uuid.uuid4()),'CFBundleName':app.stem,'CFBundleVersion':'1','CFBundlePackageType':'APPL'},f)
 try:
  data=run(['uninstall',str(app)]);assert data['dryRun'] and app.exists()
  data=run(['uninstall',str(app),'--yes']);assert not app.exists() and len(data['undoIDs'])==1
  run(['undo','restore',data['undoIDs'][0]]);assert app.exists()
 finally:shutil.rmtree(app,ignore_errors=True)
finally:shutil.rmtree(root,ignore_errors=True)
