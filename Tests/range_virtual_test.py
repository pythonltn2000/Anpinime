"""Exercise virtual-origin HTTP semantics without allocating a large file.
These tests do not claim that FilmMediaRelay forwards progressive byte ranges.
"""
import http.client
import os
TOTAL = 12_285_989_889
PORT = int(os.environ.get('ANPINIME_RANGE_PORT','8766'))

def req(path='/range', headers=None, limit=1024, method='GET'):
    print(f'RANGE_HTTP: method={method} path={path} range={(headers or {}).get("Range","")} port={PORT}',flush=True)
    c = http.client.HTTPConnection('127.0.0.1',PORT,timeout=5)
    c.request(method,path,headers=headers or {})
    r=c.getresponse(); body=r.read(limit); result=(r.status,dict(r.getheaders()),body);c.close();return result

status, headers, data=req(headers={'Range':'bytes=100-199'},limit=100)
assert status==206 and headers['Content-Range']==f'bytes 100-199/{TOTAL}' and len(data)==100 and data==bytes(i%251 for i in range(100,200))
status, headers, data=req(headers={'Range':'bytes=12285764199-'},limit=1024)
assert status==206 and headers['Content-Range']==f'bytes 12285764199-{TOTAL-1}/{TOTAL}' and len(data)==1024
status, headers, data=req(headers={'Range':'bytes=-1024'},limit=1024)
assert status==206 and headers['Content-Range']==f'bytes {TOTAL-1024}-{TOTAL-1}/{TOTAL}' and len(data)==1024
assert req(headers={'Range':f'bytes={TOTAL}-'})[0]==416
assert req(headers={'Range':'bytes=0-'})[0]==206
assert req()[0]==200
assert req('/ignore',headers={'Range':'bytes=0-2047'})[0]==200
assert req(method='HEAD')[0]==405
assert req('/redirect')[0]==302
print('PASS: virtual-origin open, closed, suffix, beyond EOF, ignored range, HEAD and redirect')
