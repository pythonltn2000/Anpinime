#!/usr/bin/env python3
import collections, io, json, re, zipfile
from pathlib import Path
outer=zipfile.ZipFile("pinedrama.ipa")
infos=outer.infolist()
large=sorted([i for i in infos if not i.is_dir()],key=lambda i:i.file_size,reverse=True)
targets=[i for i in infos if "/TikTokPineDramaImpl.bundle/" in i.filename]
print("=== PINE FILES ===")
print(json.dumps({"top_largest":[{"path":i.filename,"bytes":i.file_size} for i in large[:40]],"pine_resources":[{"path":i.filename,"bytes":i.file_size} for i in targets]},ensure_ascii=False)[:14000])
url_re=re.compile(rb'https?://[^\x00-\x20"<>\\]{5,220}',re.I)
path_re=re.compile(rb'(?i)[/][a-z0-9_/-]{2,100}(?:search|drama|episode|series|detail|play|aweme)[a-z0-9_/?=&-]{0,90}')
keyword_re=re.compile(rb'(?i)[a-z0-9_/-]{0,90}(?:drama|series|episode|book_id|series_id|play_url|search|vod|chapter|video_id)[a-z0-9_/-]{0,120}')
out={"nested_zips":[],"resources":[]}
for entry in targets:
    if entry.file_size>25_000_000: continue
    raw=outer.read(entry)
    record={"path":entry.filename,"bytes":entry.file_size}
    if zipfile.is_zipfile(io.BytesIO(raw)):
        nested=zipfile.ZipFile(io.BytesIO(raw))
        files=nested.infolist()
        record["entry_count"]=len(files)
        record["files"]=[{"path":x.filename,"bytes":x.file_size} for x in files[:100]]
        surls=collections.Counter();paths=collections.Counter();tokens=collections.Counter()
        for x in files:
            if x.file_size>18_000_000 or x.is_dir():continue
            data=nested.read(x)
            for u in url_re.findall(data):
                s=u.decode("utf8","ignore").split("?")[0].strip(",;)}")
                if len(s)<180: surls[s]+=1
            for p in path_re.findall(data):
                s=p.decode("utf8","ignore")
                if len(s)<160:paths[s]+=1
            for t in keyword_re.findall(data):
                s=t.decode("utf8","ignore")
                if len(s)<100:tokens[s]+=1
        record["urls"]=surls.most_common(45)
        record["paths"]=paths.most_common(80)
        record["tokens"]=tokens.most_common(80)
        out["nested_zips"].append(record)
    else:
        record["urls"]=[x.decode("utf8","ignore").split("?")[0] for x in url_re.findall(raw)[:50]]
        record["tokens"]=[x.decode("utf8","ignore") for x in keyword_re.findall(raw)[:100]]
        out["resources"].append(record)
Path("pinedrama_targeted_audit.json").write_text(json.dumps(out,ensure_ascii=False,indent=2))
print("=== TARGETED AUDIT START ===")
print(json.dumps(out,ensure_ascii=False,indent=2)[:55000])
print("=== TARGETED AUDIT END ===")
