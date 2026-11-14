#!/usr/bin/env python3
"""Discover palette JSON in a repository and build the static product catalogue.
No network calls. No source JSON is modified. Usage: python scripts/Sync-PaletteCatalog.py
"""
import argparse, json, re, hashlib
from pathlib import Path
HEX = re.compile(r'^#[0-9a-fA-F]{6}$')
SKIP = {'.git','.openai','node_modules','dist','__pycache__','.venv','tests'}
ANSI = ['black','red','green','yellow','blue','purple','cyan','white','brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite']
def luminance(h):
    rgb=[int(h[i:i+2],16)/255 for i in (1,3,5)]
    v=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in rgb]
    return .2126*v[0]+.7152*v[1]+.0722*v[2]
def contrast(a,b):
    x,y=sorted([luminance(a),luminance(b)])
    return (y+.05)/(x+.05)
def extract(document, source):
    """Recognize creative collections, Terminal schemes, named colors, hex arrays."""
    if isinstance(document,dict) and isinstance(document.get('palettes'),list):
        for p in document['palettes']:
            if isinstance(p,dict) and isinstance(p.get('colors'),(list,dict)):
                yield {**p,'source_file':source,'catalog_kind':'creative'}
    elif isinstance(document,dict) and isinstance(document.get('schemes'),list):
        for s in document['schemes']:
            if isinstance(s,dict) and isinstance(s.get('name'),str) and all(isinstance(s.get(k),str) and HEX.fullmatch(s[k]) for k in ['background','foreground','cursorColor','selectionBackground',*ANSI]):
                yield {'name':s['name'],'colors':[{'name':k,'hex':v,'role':k,'value_origin':'repository'} for k,v in s.items() if isinstance(v,str) and HEX.fullmatch(v)],'scheme':s,'source_file':source,'catalog_kind':'terminal'}
    elif isinstance(document,list):
        if document and all(isinstance(x,str) and HEX.fullmatch(x) for x in document):
            yield {'name':Path(source).stem.replace('-',' ').title(),'colors':document,'source_file':source,'catalog_kind':'additional'}
        else:
            for x in document:
                if isinstance(x,dict) and isinstance(x.get('colors'),(list,dict)):
                    yield {**x,'source_file':source,'catalog_kind':'additional'}
    elif isinstance(document,dict) and isinstance(document.get('colors'),(list,dict)):
        yield {**document,'name':document.get('name',Path(source).stem),'source_file':source,'catalog_kind':'additional'}
    elif isinstance(document,dict) and len(document)>=2 and all(isinstance(v,str) and HEX.fullmatch(v) for v in document.values()):
        yield {'name':Path(source).stem.replace('-',' ').title(),'colors':document,'source_file':source,'catalog_kind':'additional'}
def normalized_colors(value):
    if isinstance(value,dict):value=[{'name':k,'hex':v} for k,v in value.items()]
    out=[]
    for i,c in enumerate(value):
        if isinstance(c,str):c={'name':f'Color {i+1}','hex':c}
        if isinstance(c,dict) and isinstance(c.get('hex'),str) and HEX.fullmatch(c['hex']):
            out.append({**c,'hex':c['hex'].upper(),'name':str(c.get('name',f'Color {i+1}')),'value_origin':str(c.get('value_origin','repository'))})
    return out

def build(root):
    records=[];sources=[];warnings=[]
    for path in sorted(root.rglob('*.json')):
        if any(x in SKIP for x in path.relative_to(root).parts) or path.name in {'catalog.json','package.json','package-lock.json','repository-scan.json'}:continue
        try:
            if path.stat().st_size>5_000_000:continue
            raw=path.read_bytes();doc=json.loads(raw)
        except (ValueError,OSError) as e:
            warnings.append({'file':str(path.relative_to(root)),'message':str(e)});continue
        found=list(extract(doc,path.relative_to(root).as_posix()))
        if found:sources.append({'file':path.relative_to(root).as_posix(),'sha256':hashlib.sha256(raw).hexdigest(),'records':len(found)})
        records.extend(found)
    creative=[];schemes={}
    for p in records:
        if p['catalog_kind']=='terminal':schemes[p['name'].removeprefix('ECC | ')]=p
        else:
            colors=normalized_colors(p['colors'])
            if colors:creative.append({**p,'colors':colors})
    seen=set();out=[]
    for i,p in enumerate(creative):
        fingerprint=(p['name'],tuple(x['hex'] for x in p['colors']))
        if fingerprint in seen:continue
        seen.add(fingerprint)
        terminal=schemes.pop(p['name'],None)
        darkest=min(p['colors'],key=lambda c:luminance(c['hex']))['hex']
        scheme=terminal['scheme'] if terminal else None
        out.append({**p,'id':p.get('id',f'extra-{i+1}'),'darkest':darkest,'scheme':scheme,'scheme_source':terminal['source_file'] if terminal else None,'contrast':round(contrast(scheme['foreground'],scheme['background']),2) if scheme else None})
    for i,p in enumerate(schemes.values()):
        colors=normalized_colors(p['colors']);s=p['scheme']
        out.append({**p,'colors':colors,'id':f'terminal-{i+1}','darkest':min(colors,key=lambda c:luminance(c['hex']))['hex'],'contrast':round(contrast(s['foreground'],s['background']),2)})
    # Scan report does not imply access to inaccessible remote repositories.
    return {'schema_version':'1.0.0','collection_name':'ECC Palette Studio','palettes':out,'sources':sources,'warnings':warnings,'remote_repository_scan':{'status':'blocked','reason':'Connected GitHub exposes no repositories; previous NewRepo2 reference returned 404. No extra remote palette data claimed.'}}

def main():
    a=argparse.ArgumentParser(description=__doc__);a.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);a.add_argument('--output',type=Path);args=a.parse_args();root=args.root.resolve();out=args.output or root/'dist/data/catalog.json';catalog=build(root);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n');print(f"Catalogued {len(catalog['palettes'])} palettes from {len(catalog['sources'])} files; {len(catalog['warnings'])} warnings.")
if __name__=='__main__':main()
