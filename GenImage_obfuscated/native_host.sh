#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
DIR="$(cd "$(dirname "$0")" && pwd)"

if command -v node >/dev/null 2>&1; then
    exec node "$DIR/native_host.cjs"
fi

if command -v python3 >/dev/null 2>&1; then
    exec python3 - "$DIR" << 'PYEOF'
import sys, os, json, struct, subprocess

raw_len = sys.stdin.buffer.read(4)
if len(raw_len) < 4:
    sys.exit(0)
msg_len = struct.unpack('<I', raw_len)[0]
msg_bytes = sys.stdin.buffer.read(msg_len)
try:
    msg = json.loads(msg_bytes.decode('utf-8'))
except Exception:
    msg = {}

def send_resp(obj):
    data = json.dumps(obj).encode('utf-8')
    sys.stdout.buffer.write(struct.pack('<I', len(data)) + data)
    sys.stdout.buffer.flush()

folder_path = str(msg.get('folderPath') or '').strip()
folder_name = str(msg.get('folderName') or '').strip()
verify_file = str(msg.get('verifyFileName') or msg.get('markerFileName') or '').strip()
sample_files = msg.get('sampleFiles') or []
action = str(msg.get('action') or '').upper()

home = os.path.expanduser('~')
roots = [
    os.path.join(home, 'Downloads'),
    os.path.join(home, 'Desktop'),
    os.path.join(home, 'Pictures'),
    os.path.join(home, 'Documents'),
    home,
    '/Volumes'
]

def matches(d):
    if not os.path.isdir(d):
        return False
    if verify_file:
        return os.path.exists(os.path.join(d, verify_file))
    if sample_files:
        return any(sf and os.path.exists(os.path.join(d, sf)) for sf in sample_files)
    return True

resolved = ''
if folder_path and os.path.isabs(folder_path) and matches(folder_path):
    resolved = folder_path

if not resolved and folder_name:
    target_lower = folder_name.lower()
    for r in roots:
        try:
            if os.path.basename(r).lower() == target_lower and matches(r):
                resolved = r
                break
            direct_cand = os.path.join(r, folder_name)
            if matches(direct_cand):
                resolved = direct_cand
                break
        except Exception:
            pass

if not resolved and folder_name:
    target_lower = folder_name.lower()
    for r in roots:
        if not os.path.isdir(r):
            continue
        for cur, dirs, files in os.walk(r):
            depth = cur[len(r):].count(os.sep)
            if depth > 3:
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if not d.startswith('.') and d.lower() not in ('library', 'node_modules', '.git')]
            if os.path.basename(cur).lower() == target_lower and matches(cur):
                resolved = cur
                break
            for d in dirs:
                if d.lower() == target_lower:
                    cand = os.path.join(cur, d)
                    if matches(cand):
                        resolved = cand
                        break
            if resolved:
                break
        if resolved:
            break

if not resolved and folder_path and os.path.isdir(folder_path):
    resolved = folder_path

if action == 'OPEN_EXPLORER':
    if resolved and os.path.isdir(resolved):
        subprocess.Popen(['open', resolved])
        send_resp({'ok': True, 'opened': True, 'fullPath': resolved})
    else:
        send_resp({'ok': False, 'error': 'Folder not found', 'fullPath': resolved})
else:
    send_resp({'ok': bool(resolved), 'fullPath': resolved})
PYEOF
fi

