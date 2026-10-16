#!/usr/bin/env python3
"""
import_icons.py - put real app icons on the mini app drivers.

Icons are not shipped with this project (they are each service's trademarked
artwork).  This script copies them from sources you already have into icons/,
and tools/build.py then uses icons/<id>.png for that mini app.

  # 1) Straight from the apps installed on your Android box (needs adb,
  #    the box has USB debugging on already for Zank):
  python3 tools/import_icons.py from-box 192.168.1.50
  python3 tools/import_icons.py from-box 192.168.1.50 --only netflix,plex

  # 2) From an image, a .c4z driver you own, a zip, or an .apk:
  python3 tools/import_icons.py from-file netflix ~/Downloads/netflix.png
  python3 tools/import_icons.py from-file youtube "YouTube (Android TV).c4z"

  # icon for the custom mini app / main driver:
  python3 tools/import_icons.py from-file custom my_icon.png
  python3 tools/import_icons.py from-file zank_android_remote box.png

Then rebuild:  python3 tools/build.py
<id> is the "id" in apps.json (netflix, youtube, primevideo, ...).
"""
import argparse
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, 'icons')
IMAGE_EXT = ('.png', '.jpg', '.jpeg', '.webp')

try:
    from PIL import Image
except ImportError:
    Image = None


def image_size(data):
    if Image is not None:
        try:
            return Image.open(io.BytesIO(data)).size
        except Exception:
            return (0, 0)
    if data[:8] == b'\x89PNG\r\n\x1a\n' and len(data) >= 24:
        return struct.unpack('>II', data[16:24])
    return (0, 0)


def score_member(name, data, apk):
    """Higher is better. APK resource names are often obfuscated, so prefer
    explicit icon/banner names and fall back to the largest square-ish image."""
    w, h = image_size(data)
    if w < 48 or h < 48:
        return -1
    lname = name.lower()
    ratio = max(w, h) / max(1, min(w, h))
    s = min(w, h)
    if apk:
        if re.search(r'(ic_launcher|app_icon|launcher_icon|icon_app|ic_app|logo)', lname) and 'round' not in lname and 'foreground' not in lname and 'background' not in lname:
            s += 10000
        elif 'banner' in lname:
            s += 5000
        elif ratio > 1.3:
            return -1
        if 'notification' in lname or 'ic_stat' in lname:
            return -1
    else:
        if 'experience' in lname or 'icon' in lname or 'logo' in lname:
            s += 1000
        if ratio > 2.2:
            return -1
    return s


def best_from_archive(path):
    apk = path.lower().endswith('.apk')
    best, best_score, best_name = None, -1, None
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            if not info.filename.lower().endswith(IMAGE_EXT) or info.file_size > 8 * 1024 * 1024:
                continue
            data = z.read(info)
            sc = score_member(info.filename, data, apk)
            if sc > best_score:
                best, best_score, best_name = data, sc, info.filename
    return best, best_name


def save_icon(icon_id, data, source):
    os.makedirs(ICON_DIR, exist_ok=True)
    for ext in IMAGE_EXT:  # one icon per id
        old = os.path.join(ICON_DIR, icon_id + ext)
        if os.path.exists(old):
            os.remove(old)
    if Image is not None:
        img = Image.open(io.BytesIO(data)).convert('RGBA')
        out = os.path.join(ICON_DIR, icon_id + '.png')
        img.save(out)
    else:
        ext = '.png' if data[:4] == b'\x89PNG' else '.jpg'
        out = os.path.join(ICON_DIR, icon_id + ext)
        with open(out, 'wb') as f:
            f.write(data)
    w, h = image_size(data)
    print(f'  {icon_id:22s} <- {source}  ({w}x{h})')


def from_file(args):
    path = os.path.expanduser(args.path)
    if not os.path.exists(path):
        sys.exit(f'Not found: {path}')
    if path.lower().endswith(IMAGE_EXT):
        with open(path, 'rb') as f:
            save_icon(args.id, f.read(), os.path.basename(path))
        return
    if zipfile.is_zipfile(path):
        data, member = best_from_archive(path)
        if not data:
            sys.exit('No usable image found inside ' + path)
        save_icon(args.id, data, f'{os.path.basename(path)}:{member}')
        return
    sys.exit('Unsupported file type (use png/jpg/webp, .c4z, .zip or .apk)')


def adb(adb_bin, serial, *cmd, check=True):
    r = subprocess.run([adb_bin, '-s', serial, *cmd], capture_output=True, text=True)
    if check and r.returncode:
        raise RuntimeError(r.stderr.strip() or r.stdout.strip())
    return r.stdout


def from_box(args):
    adb_bin = args.adb or shutil.which('adb')
    if not adb_bin or not (os.path.exists(adb_bin) or shutil.which(adb_bin)):
        sys.exit('adb not found. Install Android platform-tools, or pass --adb /path/to/adb')
    serial = args.ip if ':' in args.ip else args.ip + ':5555'
    r = subprocess.run([adb_bin, 'connect', serial], capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr.strip())
    print('If the box shows an "Allow USB debugging" prompt, accept it and run this again.')
    with open(os.path.join(ROOT, 'apps.json'), encoding='utf-8') as f:
        apps = json.load(f)['apps']
    only = set(a.strip() for a in args.only.split(',')) if args.only else None
    tmp = tempfile.mkdtemp(prefix='zank_icons_')
    ok = 0
    try:
        for app in apps:
            if only and app['id'] not in only:
                continue
            try:
                paths = [l.split(':', 1)[1].strip() for l in adb(adb_bin, serial, 'shell', 'pm', 'path', app['package']).splitlines() if l.startswith('package:')]
            except RuntimeError as e:
                print(f'  {app["id"]:22s} adb error: {e}')
                continue
            if not paths:
                print(f'  {app["id"]:22s} not installed ({app["package"]})')
                continue
            base = next((p for p in paths if p.endswith('/base.apk')), paths[0])
            local = os.path.join(tmp, app['id'] + '.apk')
            try:
                adb(adb_bin, serial, 'pull', base, local)
            except RuntimeError as e:
                print(f'  {app["id"]:22s} pull failed: {e}')
                continue
            data, member = best_from_archive(local)
            if data:
                save_icon(app['id'], data, f'{app["package"]}:{member}')
                ok += 1
            else:
                print(f'  {app["id"]:22s} no bitmap icon in APK (vector-only); use from-file instead')
            os.remove(local)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f'\n{ok} icon(s) imported into {ICON_DIR}. Check them, then run: python3 tools/build.py')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='mode', required=True)
    b = sub.add_parser('from-box', help='pull icons from apps installed on the Android box via adb')
    b.add_argument('ip')
    b.add_argument('--only', help='comma-separated app ids from apps.json')
    b.add_argument('--adb', help='path to adb')
    f = sub.add_parser('from-file', help='use an image, .c4z, .zip or .apk')
    f.add_argument('id', help='app id from apps.json, "custom", or "zank_android_remote"')
    f.add_argument('path')
    a = ap.parse_args()
    {'from-box': from_box, 'from-file': from_file}[a.mode](a)


if __name__ == '__main__':
    main()
