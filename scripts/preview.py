#!/usr/bin/env python3
"""Render this repository's Markdown subset into a local review site. No dependencies."""
from pathlib import Path
import html
import re
import shutil
import sys
import subprocess
root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'dist/preview'
subprocess.run([sys.executable, str(root / "scripts/check-release-privacy.py")], check=True)
out.mkdir(parents=True, exist_ok=True)
css = '''*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#0d1117;color:#d7e0d9;font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}header{padding:18px max(24px,calc((100vw - 980px)/2));border-bottom:1px solid #27322b;display:flex;align-items:center;gap:20px;background:#0a0d0b}header strong{color:#eaf5ed;letter-spacing:-.4px}header span{font-size:12px;color:#96a69c}header a{font-size:12px}main{max-width:980px;margin:32px auto 100px;padding:32px 40px;border:1px solid #2b3530;border-radius:14px;background:#101611}h1,h2,h3{color:#f2f5ef;line-height:1.3;letter-spacing:-.5px}h1{font-size:34px;margin:28px 0 14px}h2{font-size:25px;margin:44px 0 18px;padding-bottom:12px;border-bottom:1px solid #29392e}h3{font-size:19px;margin:28px 0 12px}p{margin:14px 0}a{color:#80edb0;text-decoration:none}a:hover{text-decoration:underline}img{max-width:100%;border-radius:12px;display:block;margin:22px 0}pre{overflow:auto;padding:20px;background:#080e0a;border:1px solid #29372e;border-radius:10px;font-size:13px;line-height:1.65}code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}p code,li code,td code{font-size:85%;background:#233127;border-radius:4px;padding:2px 5px}blockquote{border-left:3px solid #9bbb91;margin:24px 0;padding:4px 18px;color:#b7c8bc;background:#18211b;border-radius:0 8px 8px 0}table{width:100%;border-collapse:collapse;margin:22px 0;font-size:14px}th,td{text-align:left;padding:13px 16px;border:1px solid #2d3a31}th{background:#18251d;color:#e8f2eb}tr:nth-child(even){background:#121d16}li{margin:8px 0}hr{border:0;border-top:1px solid #2b3a30;margin:38px 0}.pill{background:#302716;color:#f0ce89;border:1px solid #554a2d;padding:3px 9px;border-radius:99px}footer{max-width:980px;margin:0 auto 40px;color:#809889;font-size:12px;padding:0 40px}@media(max-width:700px){main{margin:14px 10px;padding:22px 18px}header{flex-wrap:wrap;padding:16px 20px;gap:8px 18px}h1{font-size:28px}table{display:block;overflow:auto}footer{padding:0 22px}}'''
def inline(text):
    tokens=[]
    def stash(value):
        tokens.append(value);return f'@@TOKEN{len(tokens)-1}@@'
    text=html.escape(text)
    text=re.sub(r'`([^`]+)`',lambda m:stash('<code>'+m[1]+'</code>'),text)
    def link(m):
        target=m[3]
        if not target.startswith(('http:','https:','mailto:','#')):
            path,sep,frag=target.partition('#')
            if path.endswith('.md'): path=path[:-3]+'.html'
            elif path in ('LICENSE','NOTICE'): path=path+'.html'
            target=path+(sep+frag if sep else '')
        if m[1]: return stash(f'<img alt="{m[2]}" src="{target}" loading="lazy">')
        return stash(f'<a href="{target}">{m[2]}</a>')
    text=re.sub(r'(!?)\[([^\]]*)\]\(([^)]+)\)',link,text)
    text=re.sub(r'\*\*([^*]+)\*\*',r'<strong>\1</strong>',text)
    for i,value in enumerate(tokens): text=text.replace(f'@@TOKEN{i}@@',value)
    return text

def render(text):
    lines=text.splitlines(); result=[];i=0
    while i<len(lines):
        line=lines[i]
        if not line.strip():i+=1;continue
        if line.startswith('```'):
            content=[];i+=1
            while i<len(lines) and not lines[i].startswith('```'):content.append(lines[i]);i+=1
            result.append('<pre><code>'+html.escape('\n'.join(content))+'</code></pre>');i+=1;continue
        if line.startswith('#'):
            level=len(line)-len(line.lstrip('#'));title=line[level:].strip()
            slug=re.sub(r'[^a-z0-9 -]','',title.lower()).replace(' ','-')
            result.append(f'<h{level} id="{slug}">{inline(title)}</h{level}>');i+=1;continue
        if line.startswith('|') and i+1<len(lines) and re.match(r'\|[\s:|-]+\|',lines[i+1]):
            cells=lambda row:[x.strip() for x in row.strip('|').split('|')]
            result.append('<table><thead><tr>'+''.join('<th>'+inline(x)+'</th>' for x in cells(line))+'</tr></thead><tbody>');i+=2
            while i<len(lines) and lines[i].startswith('|'):
                result.append('<tr>'+''.join('<td>'+inline(x)+'</td>' for x in cells(lines[i]))+'</tr>');i+=1
            result.append('</tbody></table>');continue
        if line.startswith('- '):
            result.append('<ul>')
            while i<len(lines) and lines[i].startswith('- '):result.append('<li>'+inline(lines[i][2:])+'</li>');i+=1
            result.append('</ul>');continue
        if line.startswith('> '):result.append('<blockquote>'+inline(line[2:])+'</blockquote>');i+=1;continue
        if line=='---':result.append('<hr>');i+=1;continue
        paragraph=[line];i+=1
        while i<len(lines) and lines[i].strip() and not lines[i].startswith(('#','|','- ','```','> ')):
            paragraph.append(lines[i]);i+=1
        result.append('<p>'+inline(' '.join(paragraph))+'</p>')
    return '\n'.join(result)
for source in root.rglob('*'):
    rel=source.relative_to(root)
    if any(x in {'.git','.build','.swiftpm','.module-cache','dist','__pycache__'} for x in rel.parts) or not source.is_file():continue
    dest=out/rel;dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,dest)
    if source.suffix=='.md' or source.name in ('LICENSE','NOTICE'):
        dest=dest.with_suffix('.html') if source.suffix=='.md' else dest.with_name(dest.name+'.html')
        prefix='../'*(len(rel.parts)-1)
        body=render(source.read_text())
        page=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Portkeeper · Release preview</title><style>{css}</style></head><body><header><strong>portkeeper</strong><span class="pill">LOCAL PREVIEW · NOT PUBLISHED</span><a href="{prefix}index.html">README</a><a href="{prefix}docs/GUIDE.html">Feature guide</a><a href="{prefix}THIRD_PARTY_NOTICES.html">Dependency notices</a></header><main>{body}</main><footer>Prepared for review. This local rendering approximates the GitHub README; GitHub controls its final typography and theme.</footer></body></html>'''
        dest.write_text(page)
shutil.copyfile(out/'README.html',out/'index.html')
print(out/'index.html')
