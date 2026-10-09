#!/usr/bin/env python3
"""Read Objective-C metadata from an arm64 Mach-O without executing it."""
import mmap, struct, sys, json
f=open(sys.argv[1],'rb'); d=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ)
u32=lambda p:struct.unpack_from('<I',d,p)[0]
u64=lambda p:struct.unpack_from('<Q',d,p)[0]
segments=[]; sections={}; p=32
for _ in range(u32(16)):
 cmd,size=struct.unpack_from('<II',d,p)
 if cmd==0x19:
  va,vs,fo,fs=struct.unpack_from('<QQQQ',d,p+24); segments.append((va,vs,fo,fs))
  for j in range(u32(p+64)):
   s=p+72+j*80; name=d[s:s+16].split(b'\0')[0].decode(); addr,sz=struct.unpack_from('<QQ',d,s+32); sections[name]=(addr,sz)
 p+=size
def off(a):
 a &= 0xfffffffff
 for va,vs,fo,fs in segments:
  if va<=a<va+fs:return a-va+fo
 raise ValueError(hex(a))
def string(a):
 p=off(a); return d[p:d.find(b'\0',p)].decode(errors='replace')
def methods(a):
 if not a:return []
 a &= 0xfffffffff
 p=off(a); flags,count=struct.unpack_from('<II',d,p); step=flags&0xffff; out=[]
 for j in range(count):
  e=p+8+j*step
  if flags&0x80000000:
   av=a+8+j*step; n,t=struct.unpack_from('<ii',d,e); name=av+n
   if not flags&0x40000000:name=u64(off(name))
   out.append([string(name),string(av+4+t)])
  else:out.append([string(u64(e)),string(u64(e+8))])
 return out
result={}; a,sz=sections['__objc_classlist']
for i in range(sz//8):
 try:
  cp=off(u64(off(a)+i*8)); ro=off(u64(cp+32)&~7); name=string(u64(ro+24))
  if len(sys.argv)>2 and not __import__('re').search(sys.argv[2],name):continue
  props=[]; pa=u64(ro+64)
  if pa:
   pp=off(pa); step,count=struct.unpack_from('<II',d,pp)
   for j in range(count):props.append([string(u64(pp+8+j*step)),string(u64(pp+16+j*step))])
  meta=off(u64(cp)); meta_ro=off(u64(meta+32)&~7)
  result[name]={'methods':methods(u64(ro+32)),'classMethods':methods(u64(meta_ro+32)),'properties':props}
 except (ValueError,struct.error):pass
print(json.dumps(result,indent=2))
