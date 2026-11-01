#!/usr/bin/env python3
"""Static IPA audit. No API credentials or app execution required."""
import collections, json, os, plistlib, re, struct, zipfile
from pathlib import Path

archive=Path("pinedrama.ipa")
if not archive.is_file():
    raise SystemExit("IPA not downloaded")
if not zipfile.is_zipfile(archive):
    raise SystemExit("Downloaded file is not a ZIP/IPA")

with zipfile.ZipFile(archive) as z:
    infos=z.infolist()
    files={i.filename:i for i in infos}
    apps=sorted(set(x.split(".app/")[0]+".app/" for x in files if x.startswith("Payload/") and ".app/" in x))
    root=next((x for x in apps if x.count(".app/")==1 and "/PlugIns/" not in x),None)
    if not root: raise SystemExit("Main .app directory missing")
    plist_name=root+"Info.plist"
    plist=plistlib.loads(z.read(plist_name))
    info={k:plist.get(k) for k in ["CFBundleIdentifier","CFBundleShortVersionString","CFBundleVersion","CFBundleExecutable","MinimumOSVersion","CFBundleURLTypes","NSAppTransportSecurity"] if k in plist}
    exe=root+str(plist.get("CFBundleExecutable",""))
    candidates=[]
    for i in infos:
        name=i.filename
        low=name.lower()
        if i.is_dir() or name.startswith("__MACOSX/"): continue
        if i.file_size==0:continue
        if name==exe:
            candidates.append(i); continue
        if (low.endswith((".plist",".json",".strings",".js",".html",".xml",".conf",".txt")) and i.file_size<4_000_000):
            candidates.append(i); continue
        if low.endswith((".dylib",".framework/")) and i.file_size<90_000_000: candidates.append(i)
        if ".framework/" in low and not low.endswith((".png",".jpg",".jpeg",".car",".metallib",".bundle",".xcassets",".nib",".storyboardc")) and i.file_size>100_000 and i.file_size<90_000_000:
            candidates.append(i)

    http=re.compile(rb'https?://[^\x00-\x20\x7f"<>\\]{4,250}', re.I)
    domain=re.compile(rb'(?:[a-z0-9_-]+\.)+(?:tiktok\.com|byteoversea\.com|bytedance\.com|ibytedtos\.com|byteimg\.com|tiktokcdn\.com|snssdk\.com|musical\.ly|pinedrama\.com|[a-z0-9_-]+\.(?:com|net|org|io|co|cn|app|dev))',re.I)
    apiword=re.compile(rb'(?i)(?:[a-z0-9_/.-]{0,60}(?:episode|drama|shortdrama|series|aweme|feed|play_addr|video_play|catalog|api/v[0-9]|/search/|/detail/)[a-z0-9_/.-]{0,100})')
    urls=collections.Counter(); domains=collections.Counter(); api=collections.Counter()
    perfile=collections.Counter()
    for f in candidates:
        try:
            with z.open(f) as stream:
                read_size=0
                carry=b""
                while read_size<min(180_000_000,f.file_size):
                    chunk=stream.read(1_000_000)
                    if not chunk: break
                    read_size+=len(chunk)
                    data=carry+chunk
                    carry=data[-500:]
                    for b in http.findall(data):
                        s=b.decode("utf-8","ignore").split("?")[0].split("#")[0].strip(".,);]}'")
                        if 9<len(s)<175: urls[s]+=1;perfile[f.filename]+=1
                    for b in domain.findall(data):
                        s=b.decode("ascii","ignore").lower().strip(".")
                        if 5<len(s)<100:domains[s]+=1
                    for b in apiword.findall(data):
                        s=b.decode("ascii","ignore").lower().strip(". /")
                        if 6<len(s)<140 and not s.startswith("file"):api[s]+=1
        except Exception as e:
            print("SCAN_WARNING", f.filename[:100], type(e).__name__)
    crypt = None
    try:
        data=z.read(exe)[:200000]
        if len(data)>=32 and data[:4] in (b"\xcf\xfa\xed\xfe",b"\xce\xfa\xed\xfe"):
            is64=data[:4]==b"\xcf\xfa\xed\xfe"
            ncmds=struct.unpack_from("<I",data,16)[0]
            off=32 if is64 else 28
            entries=[]
            for _ in range(min(ncmds,300)):
                if off+8>len(data):break
                cmd,sz=struct.unpack_from("<II",data,off)
                if sz<8 or off+sz>len(data):break
                if cmd in (0x21,0x2c) and sz>=20:
                    enc_off,enc_size,cryptid=struct.unpack_from("<III",data,off+8)
                    entries.append({"cryptid":cryptid,"crypted_bytes":enc_size})
                off+=sz
            crypt=entries
    except Exception as e: print("ENCRYPTION_WARNING",str(e)[:150])
    suspicious_paths=[]
    for f in infos:
        x=f.filename.lower()
        if any(t in x for t in ("ttnetwork","network","player","vod","video","drm","security","pinedrama","aweme")):
            suspicious_paths.append(f.filename)
    summary={
        "ipa_name":archive.name,"size_bytes":archive.stat().st_size,
        "entries":len(infos),"app_path":root,"app_metadata":info,
        "main_executable":exe,"main_executable_size":files[exe].file_size if exe in files else None,
        "macho_encryption_info":crypt,
        "scanned_files":len(candidates),
        "domains":domains.most_common(100),
        "url_paths":urls.most_common(100),
        "api_strings":api.most_common(100),
        "relevant_files":suspicious_paths[:100]
    }
    Path("pinedrama_ipa_audit.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2))
    print("=== IPADATA START ===")
    print(json.dumps(summary,ensure_ascii=False,indent=2)[:45000])
    print("=== IPADATA END ===")
