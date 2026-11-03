#!/usr/bin/env python3
"""Check the static site's routes, fragments, assets, metadata and sitemap."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://venkateshdas.github.io/pulse/'

class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.path, self.ids, self.refs, self.images = path, [], [], []
        self.h1 = 0
        self.title, self.canonical, self.description, self.robots = '', '', '', ''
        self.in_title = False
        self.in_json = False
        self.json_text = ''
        self.schemas = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a: self.ids.append(a['id'])
        if tag == 'h1': self.h1 += 1
        if tag == 'title': self.in_title = True
        if tag == 'link' and a.get('rel') == 'canonical': self.canonical = a.get('href', '')
        if tag == 'meta':
            if a.get('name') == 'description': self.description = a.get('content', '')
            if a.get('name') == 'robots': self.robots = a.get('content', '')
        if tag == 'script' and a.get('type') == 'application/ld+json':
            self.in_json, self.json_text = True, ''
        for key in ('href', 'src'):
            if key in a: self.refs.append(a[key])
        if tag == 'img': self.images.append(a)
    def handle_endtag(self, tag):
        if tag == 'title': self.in_title = False
        if tag == 'script' and self.in_json:
            self.schemas.append(json.loads(self.json_text))
            self.in_json = False
    def handle_data(self, data):
        if self.in_title: self.title += data
        if self.in_json: self.json_text += data

pages = {}
for path in ROOT.rglob('*.html'):
    p = Page(path); p.feed(path.read_text()); pages[path] = p
    assert p.h1 == 1, f'{path}: expected one H1'
    assert len(p.ids) == len(set(p.ids)), f'{path}: duplicate IDs'
    assert p.title, f'{path}: missing title'
    assert p.description or 'noindex' in p.robots, f'{path}: missing description'
    for img in p.images:
        assert 'alt' in img and int(img.get('width', 0)) > 0 and int(img.get('height', 0)) > 0, f'{path}: image lacks alt/dimensions'

assert len({p.title for p in pages.values()}) == len(pages), 'Duplicate page titles'
indexable = set()
for path, p in pages.items():
    if 'noindex' not in p.robots:
        route = path.relative_to(ROOT).as_posix().removesuffix('index.html')
        expected = BASE + route
        assert p.canonical == expected, f'{path}: canonical mismatch'
        indexable.add(expected)
    for ref in p.refs:
        u = urlsplit(ref)
        if u.scheme or u.netloc: continue
        target = (path.parent / unquote(u.path)).resolve() if u.path else path
        if target.is_dir(): target /= 'index.html'
        assert target.is_relative_to(ROOT), f'{path}: reference escapes site: {ref}'
        assert target.exists(), f'{path}: missing reference {ref}'
        if u.fragment and target.suffix == '.html':
            assert u.fragment in pages[target].ids, f'{path}: missing fragment {ref}'

xml = ET.parse(ROOT / 'sitemap.xml')
urls = [n.text for n in xml.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc')]
assert len(urls) == len(set(urls)) and set(urls) == indexable, 'Sitemap/indexable page mismatch'
for path, guide in pages.items():
    if path.parent.parent != ROOT / 'guides': continue
    graph = guide.schemas[0]['@graph']
    article = next(n for n in graph if n['@type'] == 'Article')
    assert article['mainEntityOfPage'] == guide.canonical
    assert article['author']['name'] == 'Pulse'
    assert article['dateModified'] in guide.path.read_text()
    assert any(n['@type'] == 'BreadcrumbList' for n in graph)
print(f'Static page checks passed: {len(pages)} pages, {len(urls)} sitemap URLs; local assets, fragments and guide schema valid.')

assert 'guides/whats-taking-up-space-on-mac/' in pages[ROOT / 'index.html'].refs, 'Homepage needs a guide entry'
assert pages[ROOT / 'index.html'].refs.count('guides/') >= 2, 'Homepage needs guide index navigation and footer links'
