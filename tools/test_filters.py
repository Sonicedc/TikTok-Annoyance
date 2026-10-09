#!/usr/bin/env python3
import pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parent.parent
prefix=(root/'Tweak.xm').read_text().split('%group ')[0].replace('#import <substrate.h>','')
start=prefix.index('// Bounded, app-local diagnostics')
end=prefix.index('// All hook signatures')
prefix=prefix[:start]+'static void TBLog(NSString *format, ...) {}\n'+prefix[end:]
with tempfile.TemporaryDirectory(prefix='tiktokblocker-tests-') as tmp:
 source=pathlib.Path(tmp)/'FilterTests.m'; source.write_text(prefix+'\n'+(root/'tests/FilterTests.m').read_text())
 binary=pathlib.Path(tmp)/'tests'
 subprocess.run(['clang','-I'+str(root),'-fobjc-arc','-fmodules-cache-path='+tmp+'/modules','-framework','Foundation',str(source),str(root/'Preferences.m'),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
