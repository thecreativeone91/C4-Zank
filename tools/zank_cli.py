#!/usr/bin/env python3
"""
zank_cli.py - talk to Zank Remote on an Android box directly (standard library only).

  python3 zank_cli.py 192.168.1.50 name                 # getName -> proves UDP works
  python3 zank_cli.py 192.168.1.50 send dpadUp          # send one UDP command
  python3 zank_cli.py 192.168.1.50 send getApps --tcp   # send over TCP (!len! framed)
  python3 zank_cli.py 192.168.1.50 probe UP             # try candidate strings for a key,
                                                        # watch the TV and answer y/n
  python3 zank_cli.py 192.168.1.50 tcpdump              # print everything the box sends on TCP

Whatever works goes in the driver's "Command Overrides" property, e.g.
  UP=dpadUp; HOME=tcp:home
"""
import argparse
import socket
import sys
import time

UDP_PORT = 1028
TCP_PORT = 1029

CANDIDATES = {
    'UP': ['dpadUp', 'up', 'DPAD_UP', 'keyUp', 'keycode 19', 'key 19', 'keyevent 19', 'KEYCODE_DPAD_UP'],
    'DOWN': ['dpadDown', 'down', 'DPAD_DOWN', 'keyDown', 'keycode 20', 'key 20', 'keyevent 20', 'KEYCODE_DPAD_DOWN'],
    'LEFT': ['dpadLeft', 'left', 'DPAD_LEFT', 'keycode 21', 'key 21', 'keyevent 21'],
    'RIGHT': ['dpadRight', 'right', 'DPAD_RIGHT', 'keycode 22', 'key 22', 'keyevent 22'],
    'SELECT': ['dpadCenter', 'ok', 'enter', 'select', 'center', 'DPAD_CENTER', 'keycode 23', 'keyevent 23'],
    'LONG_SELECT': ['longClick', 'longPress', 'longpress', 'dpadCenterLong', 'longDpadCenter', 'longCenter',
                    'centerLong', 'longOk', 'okLong', 'longPressCenter', 'longClickCenter', 'holdCenter',
                    'keycodeLong 23', 'longKeycode 23', 'keycode 23 long', 'keycode 23 true', 'longpress 23', 'longPress 23'],
    'BACK': ['back', 'BACK', 'goBack', 'keycode 4', 'keyevent 4'],
    'HOME': ['home', 'HOME', 'goHome', 'keycode 3', 'keyevent 3'],
    'PLAY_PAUSE': ['playPause', 'play_pause', 'mediaPlayPause', 'keycode 85', 'keyevent 85'],
    'LAUNCH': ['openApp {pkg}', 'launchApp {pkg}', 'launch {pkg}', 'startApp {pkg}', 'open {pkg}', 'runApp {pkg}'],
}


def udp(ip, msg, wait=1.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(wait)
    s.sendto(msg.encode(), (ip, UDP_PORT))
    replies = []
    try:
        while True:
            data, _ = s.recvfrom(65535)
            replies.append(data)
    except socket.timeout:
        pass
    return replies


def tcp(ip, msg, wait=2.0):
    payload = msg.encode()
    frame = b'!' + str(len(payload)).encode() + b'!' + payload
    s = socket.create_connection((ip, TCP_PORT), timeout=3)
    s.sendall(frame)
    s.settimeout(wait)
    out = b''
    try:
        while True:
            chunk = s.recv(65535)
            if not chunk:
                break
            out += chunk
    except socket.timeout:
        pass
    s.close()
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('ip')
    sub = ap.add_subparsers(dest='mode', required=True)
    sub.add_parser('name')
    sp = sub.add_parser('send')
    sp.add_argument('command')
    sp.add_argument('--tcp', action='store_true')
    pp = sub.add_parser('probe')
    pp.add_argument('key', choices=sorted(CANDIDATES))
    pp.add_argument('--tcp', action='store_true')
    pp.add_argument('--pkg', default='com.android.tv.settings', help='package used for LAUNCH probing')
    sub.add_parser('tcpdump')
    a = ap.parse_args()

    if a.mode == 'name':
        r = udp(a.ip, 'getName')
        print(r[0].decode(errors='replace') if r else 'No reply - is Zank Remote running on the box?')
    elif a.mode == 'send':
        if a.tcp:
            print(repr(tcp(a.ip, a.command)))
        else:
            for r in udp(a.ip, a.command):
                print(repr(r))
            print('sent')
    elif a.mode == 'probe':
        for cand in CANDIDATES[a.key]:
            cmd = cand.replace('{pkg}', a.pkg)
            print(f'\nSending {"TCP" if a.tcp else "UDP"}: {cmd}')
            if a.tcp:
                tcp(a.ip, cmd, wait=0.5)
            else:
                udp(a.ip, cmd, wait=0.3)
            ans = input('Did the box react? [y/N/q] ').strip().lower()
            if ans == 'y':
                tmpl = cand
                print(f'\nFound it. Override:  {a.key}={"tcp:" if a.tcp else ""}{tmpl}')
                return
            if ans == 'q':
                return
        print('\nNo candidate worked. Try --tcp, or capture the phone app with zank_capture.py.')
    elif a.mode == 'tcpdump':
        s = socket.create_connection((a.ip, TCP_PORT), timeout=5)
        s.settimeout(None)
        print('Connected. Ctrl+C to stop.')
        try:
            while True:
                chunk = s.recv(65535)
                if not chunk:
                    print('closed by box')
                    break
                print(repr(chunk))
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    try:
        main()
    except (ConnectionRefusedError, socket.timeout, OSError) as e:
        sys.exit(f'Network error: {e}')
