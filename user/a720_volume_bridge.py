#!/usr/bin/env python3
"""Apply Lenovo A720 absolute-volume requests to PulseAudio or PipeWire."""
from __future__ import annotations
import re, shutil, subprocess, sys, time
from pathlib import Path

BASE = Path('/sys/module/a720_wmi_handshake/parameters')
SYNC = BASE / 'sync_volume'
REQUESTED = BASE / 'requested_volume'
SEQ = BASE / 'request_seq'

def run(cmd, capture=False, check=True):
    return subprocess.run(cmd, text=True, capture_output=capture, check=check)

def backend():
    if shutil.which('pactl') and run(['pactl','info'], capture=True, check=False).returncode == 0:
        return 'pactl'
    if shutil.which('wpctl') and run(['wpctl','status'], capture=True, check=False).returncode == 0:
        return 'wpctl'
    raise RuntimeError('No working pactl or wpctl audio connection')

def get_volume(b):
    if b == 'pactl':
        out=run(['pactl','get-sink-volume','@DEFAULT_SINK@'],capture=True).stdout
        m=re.search(r'/\s*(\d+)%',out)
    else:
        out=run(['wpctl','get-volume','@DEFAULT_AUDIO_SINK@'],capture=True).stdout
        m=re.search(r'Volume:\s*([0-9]+(?:\.[0-9]+)?)',out)
        if m: return max(0,min(100,round(float(m.group(1))*100)))
    if not m: raise RuntimeError(f'Could not parse volume output: {out.strip()!r}')
    return max(0,min(100,int(m.group(1))))

def set_volume(b,v):
    v=max(0,min(100,v))
    if b == 'pactl': run(['pactl','set-sink-volume','@DEFAULT_SINK@',f'{v}%'])
    else: run(['wpctl','set-volume','@DEFAULT_AUDIO_SINK@',f'{v}%'])

def write_sync(v):
    SYNC.write_text(f'{max(0,min(100,v))}\n')

def wait_ready(timeout=45):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if all(p.exists() for p in (SYNC,REQUESTED,SEQ)):
            return
        time.sleep(.5)
    raise RuntimeError('Kernel module sysfs controls did not appear')

def main():
    wait_ready()
    b=backend()
    current=get_volume(b)
    write_sync(current)
    print(f'A720 bridge ready: backend={b}, initial volume={current}%', flush=True)
    last_seq=int(SEQ.read_text().strip())
    last_refresh=time.monotonic()
    while True:
        seq=int(SEQ.read_text().strip())
        if seq != last_seq:
            requested=int(REQUESTED.read_text().strip())
            if 0 <= requested <= 100:
                set_volume(b,requested)
                write_sync(requested)
                print(f'Lenovo bezel requested {requested}% -> applied', flush=True)
            last_seq=seq
            last_refresh=time.monotonic()
        elif time.monotonic()-last_refresh >= 2.0:
            write_sync(get_volume(b))
            last_refresh=time.monotonic()
        time.sleep(.08)

if __name__ == '__main__':
    try: main()
    except KeyboardInterrupt: pass
    except Exception as e:
        print(f'A720 bridge error: {e}', file=sys.stderr, flush=True)
        raise SystemExit(1)
