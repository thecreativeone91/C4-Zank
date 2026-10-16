#!/usr/bin/env python3
"""
Build all Control4 drivers into dist/:

  zank_android_remote.c4z            main remote + App Switcher (25 mini app inputs)
  zank_miniapp_custom.c4z            custom mini app (set name + package in Composer)
  zank_miniapp_<id>.c4z              one preset mini app per entry in apps.json

Usage:  python3 tools/build.py [--version 20261016]
Needs Pillow for icons (pip install pillow); falls back to plain icons without it.
"""
import argparse
import datetime
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
DIST = os.path.join(ROOT, 'dist')

MINIAPP_START, MINIAPP_COUNT = 3101, 25

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover
    Image = None


# ------------------------------------------------------------------ icons
def font(size):
    for p in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
              '/Library/Fonts/Arial Bold.ttf', 'C:/Windows/Fonts/arialbd.ttf'):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


PALETTE = ['#2F4B7C', '#3E6A5A', '#6B4C7A', '#7A5230', '#2E6E80', '#5B5F97', '#80484F', '#4F6D3A']


def tile_colour(name):
    return PALETTE[int(hashlib.md5(name.encode()).hexdigest(), 16) % len(PALETTE)]


def png(img):
    b = io.BytesIO()
    img.save(b, 'PNG')
    return b.getvalue()


def wrap(draw, text, fnt, width):
    words, lines, cur = text.split(), [], ''
    for w in words:
        test = (cur + ' ' + w).strip()
        if draw.textlength(test, font=fnt) <= width or not cur:
            cur = test
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def app_tile(name, size):
    """Neutral rounded tile with the app's name in plain text (no brand artwork)."""
    s = size * 4
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=s // 6, fill=tile_colour(name))
    # small "play" glyph so the tile reads as a launcher
    g = s // 7
    cx, cy = s // 2, int(s * 0.30)
    d.polygon([(cx - g // 2, cy - g // 2), (cx - g // 2, cy + g // 2), (cx + g // 2, cy)], fill='#FFFFFF')
    fsize = s // 6
    while fsize > s // 14:
        f = font(fsize)
        lines = wrap(d, name, f, s * 0.84)
        if len(lines) <= 2 and all(d.textlength(l, font=f) <= s * 0.84 for l in lines):
            break
        fsize -= 2
    f = font(fsize)
    lines = wrap(d, name, f, s * 0.84)[:2]
    y = int(s * 0.52)
    for line in lines:
        w = d.textlength(line, font=f)
        d.text(((s - w) / 2, y), line, font=f, fill='#FFFFFF')
        y += int(fsize * 1.15)
    return img.resize((size, size), Image.LANCZOS)


def box_icon(size):
    """Generic streaming-box glyph for the main driver."""
    s = size * 4
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([s * 0.08, s * 0.30, s * 0.92, s * 0.70], radius=s // 10, fill='#33373D')
    d.rounded_rectangle([s * 0.08, s * 0.30, s * 0.92, s * 0.40], radius=s // 10, fill='#4A5058')
    d.ellipse([s * 0.74, s * 0.52, s * 0.82, s * 0.60], fill='#3DDC84')
    d.rectangle([s * 0.18, s * 0.54, s * 0.55, s * 0.58], fill='#6C737C')
    return img.resize((size, size), Image.LANCZOS)


ICON_DIR = os.path.join(ROOT, 'icons')


def custom_icon(icon_id):
    """icons/<id>.png (or .jpg/.webp) supplied by you; fitted onto a transparent square."""
    if Image is None or not icon_id:
        return None
    for ext in ('png', 'jpg', 'jpeg', 'webp'):
        path = os.path.join(ICON_DIR, f'{icon_id}.{ext}')
        if os.path.exists(path):
            src = Image.open(path).convert('RGBA')
            bbox = src.getbbox()
            if bbox:
                src = src.crop(bbox)
            side = max(src.size)
            sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
            sq.paste(src, ((side - src.width) // 2, (side - src.height) // 2), src)
            return lambda sz: sq.resize((sz, sz), Image.LANCZOS)
    return None


def icon_files(kind, name, icon_id=None):
    files = {}
    if Image is None:
        blank = bytes.fromhex('89504e470d0a1a0a0000000d4948445200000001000000010806000000'
                              '1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082')
        for n in ('device_sm', 'device_lg', 'experience_70', 'experience_90', 'experience_300', 'experience_512'):
            files[f'www/icons/{n}.png'] = blank
        return files
    draw = custom_icon(icon_id) or (box_icon if kind == 'main' else (lambda sz: app_tile(name, sz)))
    files['www/icons/device_sm.png'] = png(draw(16))
    files['www/icons/device_lg.png'] = png(draw(32))
    for sz in (70, 90, 300, 512):
        files[f'www/icons/experience_{sz}.png'] = png(draw(sz))
    return files


# ------------------------------------------------------------------ helpers
def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def lua_str(s):
    return "'" + str(s).replace('\\', '\\\\').replace("'", "\\'") + "'"


def check_xml(name, xml):
    for m in re.finditer(r'<!--(.*?)-->', xml, re.S):
        if '--' in m.group(1):
            raise SystemExit(f'{name}: illegal "--" inside an XML comment')
    if shutil.which('xmllint'):
        r = subprocess.run(['xmllint', '--noout', '-'], input=xml.encode(), capture_output=True)
        if r.returncode:
            raise SystemExit(f'{name}: XML invalid\n{r.stderr.decode()}')
    else:
        import xml.dom.minidom
        xml.dom.minidom.parseString(xml)


def check_lua(name, lua):
    for tool in ('luac5.1', 'luac', 'texluac'):
        if shutil.which(tool):
            tmp = os.path.join(DIST, '.check.lua')
            with open(tmp, 'w', encoding='utf-8') as f:
                f.write(lua)
            r = subprocess.run([tool, '-p', tmp], capture_output=True)
            os.remove(tmp)
            if r.returncode:
                raise SystemExit(f'{name}: Lua syntax error\n{r.stderr.decode()}')
            return
    print('  (no luac found, Lua syntax not checked)')


def write_c4z(filename, files):
    path = os.path.join(DIST, filename)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for arc in sorted(files, key=lambda a: (a not in ('driver.xml', 'driver.lua'), a)):
            data = files[arc]
            z.writestr(arc, data if isinstance(data, bytes) else data.encode('utf-8'))
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
    assert 'driver.xml' in names and 'driver.lua' in names, f'{filename}: driver.xml/driver.lua missing at root'
    return path, names


def documentation_html():
    md = read(os.path.join(ROOT, 'README.md'))
    body = []
    in_code = False
    for line in md.splitlines():
        if line.startswith('```'):
            body.append('</pre>' if in_code else '<pre>')
            in_code = not in_code
            continue
        if in_code:
            body.append(escape(line))
            continue
        h = re.match(r'^(#+)\s+(.*)', line)
        if h:
            n = min(len(h.group(1)), 4)
            body.append(f'<h{n}>{escape(h.group(2))}</h{n}>')
        elif line.strip().startswith(('- ', '* ')):
            body.append('<li>' + escape(line.strip()[2:]) + '</li>')
        elif line.strip():
            body.append('<p>' + escape(line) + '</p>')
    html = '\n'.join(body)
    html = re.sub(r'`([^`]+)`', r'<code>\1</code>', html)
    html = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', html)
    return ('<!DOCTYPE html><html><head><meta charset="utf-8"><title>Zank Android Remote</title>'
            '<style>body{font-family:sans-serif;max-width:860px;margin:16px;line-height:1.45}'
            'pre,code{background:#f2f2f2;padding:2px 4px}pre{padding:8px;overflow:auto}</style>'
            '</head><body>' + html + '</body></html>')


# ------------------------------------------------------------------ build
def build_main(version, modified, apps):
    d = os.path.join(SRC, 'zank_android_remote')
    xml = read(os.path.join(d, 'driver.xml'))
    lua = read(os.path.join(d, 'driver.lua'))

    inputs = []
    for i in range(MINIAPP_COUNT):
        inputs.append(f'''		<connection proxybindingid="5002">
			<id>{MINIAPP_START + i}</id>
			<facing>6</facing>
			<connectionname>Android App {i + 1}</connectionname>
			<type>5</type>
			<consumer>True</consumer>
			<audiosource>False</audiosource>
			<videosource>True</videosource>
			<linelevel>False</linelevel>
			<classes>
				<class>
					<classname>RF_ANDROID_APP</classname>
				</class>
			</classes>
		</connection>''')
    keys = re.search(r'KEY_LIST = \{(.*?)\}', lua, re.S).group(1)
    key_items = '\n'.join(f'\t\t\t\t\t\t\t<item>{k}</item>' for k in re.findall(r"'([A-Z0-9_]+)'", keys))

    xml = (xml.replace('@@MINIAPP_INPUTS@@', '\n'.join(inputs))
              .replace('@@KEY_ITEMS@@', key_items)
              .replace('@@VERSION@@', version).replace('@@MODIFIED@@', modified))
    presets = 'APP_PRESETS = {\n' + ''.join(
        f"  {{ name = {lua_str(a['name'])}, package = {lua_str(a['package'])} }},\n" for a in apps) + '}'
    lua = lua.replace('--@@PRESETS@@', presets)

    check_xml('zank_android_remote', xml)
    check_lua('zank_android_remote', lua)
    files = {'driver.xml': xml, 'driver.lua': lua, 'www/documentation/index.html': documentation_html()}
    files.update(icon_files('main', 'Zank', 'zank_android_remote'))
    return write_c4z('zank_android_remote.c4z', files)


def build_miniapp(version, modified, app_id, name, package, custom=False):
    d = os.path.join(SRC, 'zank_miniapp')
    file_stem = f'zank_miniapp_{app_id}'
    display = 'Zank Custom Mini App' if custom else f'{name} (Zank)'
    model = 'Custom Mini App' if custom else f'{name} Mini App'
    xml = read(os.path.join(d, 'driver.xml'))
    xml = (xml.replace('@@NAME@@', escape(display)).replace('@@MODEL@@', escape(model))
              .replace('@@APP_NAME@@', escape('' if custom else name))
              .replace('@@PACKAGE@@', escape(package))
              .replace('@@DRIVER_FILE@@', file_stem)
              .replace('@@OUT_NAME@@', escape('App' if custom else name))
              .replace('@@VERSION@@', version).replace('@@MODIFIED@@', modified))
    lua = read(os.path.join(d, 'driver.lua'))
    preset = f"PRESET = {{ name = {lua_str('' if custom else name)}, package = {lua_str(package)}, activity = '' }}"
    lua = lua.replace('--@@PRESET@@', preset)
    check_xml(file_stem, xml)
    check_lua(file_stem, lua)
    files = {'driver.xml': xml, 'driver.lua': lua}
    files.update(icon_files('app', 'Custom App' if custom else name, app_id))
    return write_c4z(file_stem + '.c4z', files)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', default=datetime.date.today().strftime('%Y%m%d'))
    a = ap.parse_args()
    modified = datetime.datetime.now().strftime('%m/%d/%Y %I:%M %p')
    apps = json.loads(read(os.path.join(ROOT, 'apps.json')))['apps']
    if os.path.isdir(DIST):
        shutil.rmtree(DIST)
    os.makedirs(DIST)

    built = [build_main(a.version, modified, apps)]
    built.append(build_miniapp(a.version, modified, 'custom', '', '', custom=True))
    for app in apps:
        built.append(build_miniapp(a.version, modified, app['id'], app['name'], app['package']))

    with zipfile.ZipFile(os.path.join(DIST, 'zank-c4-drivers.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
        for path, _ in built:
            z.write(path, os.path.basename(path))
    # export built Lua for tests/run_tests.lua
    tb = os.path.join(ROOT, 'tests', 'build')
    os.makedirs(tb, exist_ok=True)
    for c4z, out in (('zank_android_remote.c4z', 'remote.lua'), ('zank_miniapp_netflix.c4z', 'miniapp_netflix.lua')):
        with zipfile.ZipFile(os.path.join(DIST, c4z)) as z, open(os.path.join(tb, out), 'wb') as f:
            f.write(z.read('driver.lua'))
    for path, names in built:
        print(f'  {os.path.basename(path):40s} {len(names)} files')
    custom = sorted(os.path.splitext(f)[0] for f in os.listdir(ICON_DIR) if f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp'))) if os.path.isdir(ICON_DIR) else []
    print('Custom icons used: ' + (', '.join(custom) if custom else 'none (generated tiles)'))
    print(f'Built {len(built)} drivers (version {a.version}) into {DIST}')


if __name__ == '__main__':
    sys.exit(main())
