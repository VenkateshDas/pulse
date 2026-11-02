"""Deterministic UI replicas. Fictional data only; never reads the host Mac."""
from html import escape
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[1] / 'assets'

def render(name, mode, page):
    dark = mode == 'dark'
    bg, surface, sidebar, ink, muted, accent, line = (
        ('#171d21','#222b30','#1b2524','#f2f6f7','#b5c2c9','#70d6b3','#52616a') if dark else
        ('#f5f7f8','#ffffff','#f0f4f3','#172126','#4f6068','#176b56','#ccd5da'))
    on_accent = '#103e31' if dark else '#ffffff'
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="1040" viewBox="0 0 1440 1040" role="img" aria-labelledby="title desc"><title id="title">Pulse {escape(page)} UI demo</title><desc id="desc">Faithful interface replica with entirely fictional sample data. Not a screenshot of a real Mac.</desc><style>text{{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;fill:{ink}}}.muted{{fill:{muted}}}.accent{{fill:{accent}}}.num{{font-variant-numeric:tabular-nums}}.on-accent{{fill:{on_accent}}}</style>']
    def rect(x,y,w,h,fill=surface,r=10,stroke=None):
        out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+'/>')
    def txt(x,y,text,size=17,weight=400,cls='',anchor='start'):
        out.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" class="{cls}" text-anchor="{anchor}">{escape(text)}</text>')
    def rule(x,y,w): out.append(f'<path d="M{x} {y}h{w}" stroke="{line}"/>')
    def folder(x,y):
        out.append(f'<path d="M{x} {y+4}h11l4 4h15v20H{x}z" fill="{accent}" opacity=".8"/>')
    def chevron(x,y,left=False):
        points = f'M{x+5} {y-5}l-5 5 5 5' if left else f'M{x} {y-5}l5 5-5 5'
        out.append(f'<path d="{points}" fill="none" stroke="{muted}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>')
    def box(x,y,w,h):rect(x,y,w,h,surface,10,line)
    rect(0,0,1440,1040,bg,14);rect(0,0,270,1040,sidebar,14)
    rect(26,28,38,38,accent,9);txt(36,55,'p',32,600,'on-accent');txt(78,57,'Pulse',29,650)
    items=['Home','Free up space','Apps','Battery & energy','Internet','Displays','Activity','App activity','Maintenance','Startup helpers','Performance test','Diagnostics','Settings']
    selected = 'Free up space' if page=='Files' else page
    for i,item in enumerate(items):
        y=112+i*57
        if item==selected:rect(18,y-27,234,44,accent,7);out.append(f'<rect x="18" y="{y-27}" width="234" height="44" rx="7" fill="{sidebar}" opacity=".87"/>')
        # Consistent small line icons, without substituting emoji or glyph art.
        out.append(f'<g stroke="{accent if item==selected else muted}" stroke-width="1.6" fill="none"><rect x="33" y="{y-17}" width="17" height="17" rx="3"/><path d="M37 {y-9}h9M41 {y-14}v10"/></g>')
        txt(67,y,item,17,600 if item==selected else 400,'accent' if item==selected else '')
    txt(30,1006,'Interface preview',14,400,'muted');txt(308,1006,'DEMO DATA · Fictional examples · No access to your Mac',14,500,'muted')
    if page=='Home':
        txt(310,62,'Home',32,650);txt(310,95,'A clearer picture of your Mac. A more considered next step.',17,400,'muted')
        box(310,130,1090,150);txt(336,171,'No urgent issues detected',24,600)
        txt(336,205,'The available readings show no urgent problems. You can keep working',16,400,'muted');txt(336,231,'or choose a task below.',16,400,'muted');txt(336,258,'Example status · Demo data',13,400,'muted')
        box(310,310,1090,105)
        for x,label,value in [(336,'Storage','64 GB available'),(680,'Battery','82% charged'),(1020,'Internet','Connected to a network')]:
            txt(x,348,label,15,400,'muted');txt(x,381,value,18,600)
        chevron(312,447);txt(332,453,'Technical details',16,500,'muted')
        box(310,488,1090,350);txt(336,525,'What would you like to do?',20,600)
        for i,(title,sub) in enumerate([('Review cleanup','Choose files to move to Trash. Nothing is removed during a scan.'),('Remove an app','Review the app and its related files before removing them.'),('Check a slowdown','See which apps are busy and review the process details.'),('Adjust brightness','Make your screens more comfortable to use.')]):
            y=569+i*73;txt(345,y,title,18,550);txt(345,y+25,sub,14,400,'muted');chevron(1365,y+6)
            if i<3:rule(336,y+40,1036)
        txt(310,892,'Recent removal',19,600);txt(310,929,'Nothing removed in this demo.',15,400,'muted')
    elif page=='Files':
        for i,label in enumerate(['Cleanup','Files','Duplicates','Changes','Trash']):
            x=310+i*150;rect(x,22,145,35,line if label=='Files' else surface,6);txt(x+72,46,label,17,500,anchor='middle')
        rule(270,80,1170);rect(270,81,1170,61,surface,0);txt(305,119,'Demo Disk',21,600);chevron(420,112);txt(445,119,'Library',21,600);chevron(530,112);txt(555,119,'Application Support',21,600)
        cols=[ [('Library','192 GB'),('Users','128 GB'),('System','96 GB'),('Applications','32 GB')], [('Application Support','128 GB'),('Caches','32 GB'),('Frameworks','16 GB'),('Updates','16 GB')], [('Sample Studio','72 GB'),('Demo Browser','32 GB'),('Audio Library','16 GB'),('Shared Assets','8 GB')] ]
        for c,rows in enumerate(cols):
            x=290+c*375
            largest = max(float(size.split()[0]) for _, size in rows)
            for i,(label,size) in enumerate(rows):
                y=182+i*86
                if c<2 and i==0:rect(x,y-26,356,72,accent,6);rect(x,y-26,356,72,sidebar,6);out.append(f'<rect x="{x}" y="{y-26}" width="356" height="72" rx="6" fill="{accent}" opacity=".13"/>')
                folder(x+10,y-19);txt(x+52,y+3,label,18,550 if i==0 else 400);txt(x+337,y+29,size,17,500,'num','end')
                rect(x+52,y+19,174,4,line,2);rect(x+52,y+19,round(174 * float(size.split()[0]) / largest),4,accent,2)
            if c<2:out.append(f'<path d="M{x+365} 142v800" stroke="{line}"/>')
        rect(270,933,1170,47,surface,0);txt(305,964,'Demo Disk',17,600);txt(1390,964,'Used: 448 GB   Purgeable: 20 GB   Free: 64 GB   Total: 512 GB',16,500,'num','end')
    elif page=='App activity':
        txt(310,62,'App activity',32,650);txt(310,99,'See which apps are busy. High use can be normal; review details first.',17,400,'muted')
        rect(310,120,220,38,surface,6);txt(325,145,'Measure a slowdown…',16,500)
        box(310,193,1090,640);txt(337,233,'Apps and processes',19,600);txt(1370,233,'Group by app · CPU',16,500,'accent','end')
        rect(334,259,1042,44,bg,6);txt(350,287,'Filter by name',16,400,'muted')
        for x,t in [(350,'NAME'),(1020,'CPU'),(1190,'MEM')]:txt(x,342,t,14,550,'muted')
        for i,(label,cpu,mem) in enumerate([('Demo Browser (8)','27.0%','1.2 GB'),('Sample Editor (4)','8.0%','512 MB'),('Music Player (2)','2.0%','128 MB'),('Notes (1)','0.5%','64 MB')]):
            y=397+i*64;rect(347,y-17,9,9,accent,4);txt(370,y,label,18,500);txt(1090,y,cpu,18,400,'num','end');txt(1335,y,mem,18,400,'num','end');rule(335,y+24,1040)
        txt(337,793,'Fictional apps and readings for this interface preview.',15,400,'muted')
    elif page=='Apps':
        txt(310,62,'Apps',32,650);txt(310,99,'Choose an app, review its related files, then move selected items to Trash.',16,400,'muted')
        txt(310,127,'They still use storage until Trash is emptied.',16,400,'muted')
        box(310,190,1090,660);chevron(335,225,True);txt(359,232,'Review removal',19,600);txt(1370,232,'2 related files found',16,500,'muted','end')
        for i,(title,sub,size) in enumerate([('Sample Studio','App bundle · included in removal','82 MB'),('com.example.sample-studio','Container · matches bundle ID','4 MB'),('com.example.sample-studio','App scripts · matches bundle ID','1 MB')]):
            y=287+i*108;rect(334,y-22,1042,84,bg,7);rect(350,y-4,17,17,accent,3);txt(384,y+8,title,19,600);txt(384,y+37,sub,15,400,'muted');txt(1350,y+14,size,18,600,'num','end')
        txt(335,640,'Related files can contain preferences or documents.',17,500);txt(335,673,'Leave anything you want to keep unselected.',17,400,'muted');txt(335,706,'Restore from Trash before emptying it.',17,400,'muted')
        rect(335,748,1040,52,accent,7);txt(855,781,'Move selected items to Trash',18,600,'on-accent',anchor='middle')
    out.append('</svg>');path=ASSETS/name;path.write_text('\n'.join(out)+'\n')

for name,theme,page in [('pulse-demo-home-light.svg','light','Home'),('pulse-demo-home-dark.svg','dark','Home'),('pulse-demo-storage.svg','dark','Files'),('pulse-demo-activity.svg','dark','App activity'),('pulse-demo-app-review.svg','dark','Apps')]:
    render(name,theme,page)
