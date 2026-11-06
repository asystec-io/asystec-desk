#!/usr/bin/env bash
# Upgrade an existing book service without changing its TLS or enrollment configuration.
set -euo pipefail
cd "$(dirname "$0")"
base=/opt/asystec-book
db=/var/lib/asystec-book/libreta.sqlite3
keys=/etc/asystec-book
test "$(id -u)" = 0 && test -f "$db" && test -x "$base/venv/bin/python"
install -d -m 0700 "$keys"
umask 077
exec 9>"$keys/vault.lock"
flock 9
python3 - "$db" "$keys/vault.key" <<'PY'
import os, secrets, sqlite3, sys
from pathlib import Path
db, key = sys.argv[1], Path(sys.argv[2])
if not key.exists():
    with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as conn:
        exists = conn.execute("SELECT 1 FROM sqlite_master WHERE name='credential'").fetchone()
        if exists and conn.execute('SELECT 1 FROM credential WHERE sealed IS NOT NULL LIMIT 1').fetchone():
            sys.exit('Restore the existing credential key from backup.')
    new = key.with_suffix('.tmp')
    with new.open('wb') as out:
        out.write(secrets.token_bytes(32))
        out.flush()
        os.fsync(out.fileno())
    os.replace(new, key)
if key.stat().st_size != 32:
    sys.exit('Invalid credential key. Restore from backup.')
PY
chmod 0600 "$keys/vault.key"
umask 022
"$base/venv/bin/pip" -q install -r requirements.txt
sudo -u desk-book "$base/venv/bin/python" -c "from cryptography.hazmat.primitives.ciphers.aead import AESGCM"
install -m 0644 service.py requirements.txt "$base/"
install -d -m 0755 /etc/systemd/system/asystec-book.service.d
cat > /etc/systemd/system/asystec-book.service.d/credentials.conf <<'UNIT'
[Service]
LoadCredential=vault.key:/etc/asystec-book/vault.key
Environment=BOOK_CREDENTIAL_KEY=%d/vault.key
UNIT
systemctl daemon-reload
systemctl restart asystec-book
curl --fail --retry 8 --retry-connrefused --silent http://127.0.0.1:8787/api/login-options
