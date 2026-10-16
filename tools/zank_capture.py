#!/usr/bin/env python3
"""
zank_capture.py - learn the exact commands your Zank Remote version uses.

Two ways to capture (standard library only, Python 3.8+):

1) Fake TV ("wizard") - run on a PC on the same LAN as your phone:
       python3 zank_capture.py wizard
   In the Zank phone app, search for devices and pick this PC (it answers
   "getName" on UDP 1028 just like the box).  The wizard asks you to press each
   button, records what the phone sends, and prints a ready-to-paste
   "Command Overrides" line for the Control4 driver.

   Note: some Zank versions only fully talk to a real box.  If buttons never
   show up here, use option 2.

2) Packet capture - control the REAL box with the phone while capturing:
   - Android phone: install PCAPdroid, capture the Zank app, export a .pcap
   - or Wireshark on a PC / mirrored switch port
   then:
       python3 zank_capture.py pcap capture.pcap
   Prints every payload sent to ports 1028/1029 in order.

Other modes:
       python3 zank_capture.py listen        # just log everything received
"""
import argparse
import queue
import re
import socket
import struct
import sys
import threading
import time

UDP_PORT = 1028
TCP_PORT = 1029

NOISE = re.compile(r'^(getName|move|hideMouse|ping)\b', re.I)

WIZARD_KEYS = [
    ('UP', 'D-pad UP'), ('DOWN', 'D-pad DOWN'), ('LEFT', 'D-pad LEFT'),
    ('RIGHT', 'D-pad RIGHT'), ('SELECT', 'OK / centre'), ('LONG_SELECT', 'LONG-PRESS OK / centre (hold it ~1s)'), ('BACK', 'BACK'),
    ('HOME', 'HOME'), ('MENU', 'MENU (if present)'), ('RECENTS', 'RECENT APPS (if present)'),
    ('PLAY_PAUSE', 'PLAY/PAUSE'), ('NEXT', 'NEXT / skip forward'), ('PREVIOUS', 'PREVIOUS / skip back'),
    ('FAST_FORWARD', 'FAST FORWARD'), ('REWIND', 'REWIND'), ('STOP', 'STOP (if present)'),
    ('VOLUME_UP', 'VOLUME UP'), ('VOLUME_DOWN', 'VOLUME DOWN'), ('MUTE', 'MUTE'),
    ('POWER', 'POWER (if present)'), ('SEARCH', 'SEARCH / voice (if present)'),
    ('APP_LIST', 'open the APPS list / app launcher screen'),
    ('LAUNCH', 'launch any app from the app list (e.g. Netflix)'),
    ('TEXT', 'open the keyboard, type  hello  and press send/enter'),
]

PKG_RE = re.compile(r'[A-Za-z_][\w]*(?:\.[\w]+){1,}')


def decode_frames(buf):
    """Split '!len!payload' frames; returns (frames, remainder)."""
    frames = []
    while True:
        m = re.match(rb'^!(\d+)!', buf)
        if not m:
            break
        n = int(m.group(1))
        start = m.end()
        if len(buf) < start + n:
            break
        frames.append(buf[start:start + n])
        buf = buf[start + n:]
    return frames, buf


def show(b):
    try:
        s = b.decode('utf-8')
        if all(ch.isprintable() or ch in '\r\n\t' for ch in s):
            return s
    except UnicodeDecodeError:
        pass
    return repr(b)


class FakeTv:
    def __init__(self, name, verbose=True):
        self.name = name
        self.verbose = verbose
        self.events = queue.Queue()
        self.stop = threading.Event()

    def start(self):
        threading.Thread(target=self.udp_loop, daemon=True).start()
        threading.Thread(target=self.tcp_loop, daemon=True).start()

    def emit(self, transport, src, data):
        text = show(data).strip()
        if self.verbose:
            print(f'  [{time.strftime("%H:%M:%S")}] {transport} {src[0]}:{src[1]} -> {text}')
        self.events.put((transport, text))

    def udp_loop(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.bind(('0.0.0.0', UDP_PORT))
        print(f'UDP listening on {UDP_PORT} (answering getName as "{self.name}")')
        while not self.stop.is_set():
            data, addr = s.recvfrom(65535)
            if data.startswith(b'getName'):
                s.sendto(self.name.encode(), addr)
            self.emit('UDP', addr, data)

    def tcp_loop(self):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(('0.0.0.0', TCP_PORT))
        srv.listen(5)
        print(f'TCP listening on {TCP_PORT}')
        while not self.stop.is_set():
            conn, addr = srv.accept()
            threading.Thread(target=self.tcp_client, args=(conn, addr), daemon=True).start()

    def tcp_client(self, conn, addr):
        print(f'  TCP client connected from {addr[0]}:{addr[1]}')
        buf = b''
        with conn:
            while True:
                chunk = conn.recv(65535)
                if not chunk:
                    break
                buf += chunk
                frames, buf = decode_frames(buf)
                for f in frames:
                    self.emit('TCP', addr, f)
                if buf and not buf.startswith(b'!'):
                    for line in buf.splitlines():
                        if line.strip():
                            self.emit('TCP-raw', addr, line)
                    buf = b''
        print(f'  TCP client {addr[0]} disconnected')


def to_template(key, text):
    if key == 'LAUNCH':
        m = PKG_RE.search(text)
        if m:
            return text.replace(m.group(0), '{pkg}')
    if key == 'TEXT' and 'hello' in text:
        return text.replace('hello', '{text}')
    return text


def wizard(args):
    tv = FakeTv(args.name, verbose=True)
    tv.start()
    print('\nIn the Zank phone app: search for devices and connect to "%s".' % args.name)
    input('Press Enter here once the phone shows it as connected... ')
    results = {}
    for key, label in WIZARD_KEYS:
        while not tv.events.empty():
            tv.events.get_nowait()
        print(f'\n>>> Press {label} in the phone app  (wait {args.timeout}s, or Ctrl+C to skip this key)')
        got = None
        deadline = time.time() + args.timeout
        try:
            while time.time() < deadline:
                try:
                    transport, text = tv.events.get(timeout=0.5)
                except queue.Empty:
                    continue
                if NOISE.match(text) or not text:
                    continue
                got = (transport, text)
                time.sleep(0.4)  # let any trailing message arrive
                break
        except KeyboardInterrupt:
            print('  skipped')
            continue
        if got:
            transport, text = got
            tmpl = to_template(key, text)
            prefix = 'tcp:' if transport.startswith('TCP') else ''
            results[key] = prefix + tmpl
            print(f'  captured {key} = {prefix}{tmpl}')
        else:
            print('  nothing captured')
    print_overrides(results)


def print_overrides(results):
    if not results:
        print('\nNothing captured.')
        return
    print('\n' + '=' * 70)
    print('Paste this into the driver property "Command Overrides":\n')
    print('; '.join(f'{k}={v}' for k, v in results.items()))
    print('=' * 70)
    print('Then run the driver action "Print Command Map" to confirm.')


def listen(args):
    tv = FakeTv(args.name, verbose=True)
    tv.start()
    print('Logging everything. Ctrl+C to stop.')
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass


# ---------------------------------------------------------------- pcap parsing
def iter_pcap(path):
    with open(path, 'rb') as f:
        gh = f.read(24)
        if len(gh) < 24:
            raise SystemExit('Not a pcap file')
        magic = gh[:4]
        if magic in (b'\xd4\xc3\xb2\xa1', b'\x4d\x3c\xb2\xa1'):
            endian = '<'
        elif magic in (b'\xa1\xb2\xc3\xd4', b'\xa1\xb2\x3c\x4d'):
            endian = '>'
        elif magic == b'\x0a\x0d\x0d\x0a':
            raise SystemExit('This is pcapng - export as classic .pcap (PCAPdroid: Settings > PCAP format, or "editcap -F pcap in.pcapng out.pcap")')
        else:
            raise SystemExit('Unknown capture format')
        linktype = struct.unpack(endian + 'I', gh[20:24])[0]
        while True:
            rh = f.read(16)
            if len(rh) < 16:
                return
            ts, _, incl, _ = struct.unpack(endian + 'IIII', rh)
            yield ts, linktype, f.read(incl)


def ip_payload(linktype, pkt):
    if linktype == 1:            # Ethernet
        if len(pkt) < 14:
            return None
        etype = struct.unpack('!H', pkt[12:14])[0]
        off = 14
        if etype == 0x8100:
            etype = struct.unpack('!H', pkt[16:18])[0]
            off = 18
        return pkt[off:] if etype == 0x0800 else None
    if linktype in (101, 12, 228):  # raw IPv4
        return pkt
    if linktype == 113:          # Linux cooked
        return pkt[16:]
    if linktype == 276:          # Linux cooked v2
        return pkt[20:]
    return None


def pcap(args):
    streams = {}
    count = 0
    for ts, lt, pkt in iter_pcap(args.file):
        ip = ip_payload(lt, pkt)
        if not ip or (ip[0] >> 4) != 4:
            continue
        ihl = (ip[0] & 0x0F) * 4
        proto = ip[9]
        src = socket.inet_ntoa(ip[12:16])
        dst = socket.inet_ntoa(ip[16:20])
        seg = ip[ihl:]
        if proto == 17 and len(seg) >= 8:
            sport, dport = struct.unpack('!HH', seg[:4])
            data = seg[8:]
            transport = 'UDP'
        elif proto == 6 and len(seg) >= 20:
            sport, dport = struct.unpack('!HH', seg[:4])
            data = seg[(seg[12] >> 4) * 4:]
            transport = 'TCP'
        else:
            continue
        if not data or (dport not in (UDP_PORT, TCP_PORT) and sport not in (UDP_PORT, TCP_PORT)):
            continue
        direction = 'phone->box' if dport in (UDP_PORT, TCP_PORT) else 'box->phone'
        if direction == 'box->phone' and not args.both:
            continue
        stamp = time.strftime('%H:%M:%S', time.localtime(ts))
        if transport == 'TCP':
            key = (src, sport, dst, dport)
            streams[key] = streams.get(key, b'') + data
            frames, streams[key] = decode_frames(streams[key])
            if not frames and streams[key] and not streams[key].startswith(b'!'):
                frames, streams[key] = [streams[key]], b''
            for fr in frames:
                count += 1
                print(f'{stamp} {transport} {direction} {src}->{dst}:{dport}  {show(fr)[:300]}')
        else:
            count += 1
            print(f'{stamp} {transport} {direction} {src}->{dst}:{dport}  {show(data)[:300]}')
    print(f'\n{count} Zank messages found.')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='mode', required=True)
    w = sub.add_parser('wizard', help='fake Zank TV, guided button capture')
    w.add_argument('--name', default='Zank Capture PC')
    w.add_argument('--timeout', type=int, default=20)
    l = sub.add_parser('listen', help='fake Zank TV, log everything')
    l.add_argument('--name', default='Zank Capture PC')
    p = sub.add_parser('pcap', help='extract Zank messages from a .pcap')
    p.add_argument('file')
    p.add_argument('--both', action='store_true', help='also show box->phone replies (app lists etc.)')
    args = ap.parse_args()
    {'wizard': wizard, 'listen': listen, 'pcap': pcap}[args.mode](args)


if __name__ == '__main__':
    try:
        main()
    except PermissionError:
        sys.exit('Permission denied binding the ports - close other Zank servers or run as admin.')
