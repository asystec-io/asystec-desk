#!/usr/bin/env bash
# Enable installation enrollment for the already provisioned Asystec account.
set -euo pipefail
cd "$(dirname "$0")"
base=/opt/asystec-book
config=/etc/asystec-book-enrollment.env
guid=$(python3 - <<'PY'
import re, sqlite3
with sqlite3.connect('file:/var/lib/asystec-book/libreta.sqlite3?mode=ro', uri=True) as db:
    row = db.execute("SELECT guid FROM account WHERE name='asystec'").fetchone()
    if not row or not re.fullmatch(r'asystec-[a-f0-9]{32}', row[0]):
        raise SystemExit('Falta la cuenta asystec.')
    print(row[0])
PY
)
if [[ -f "$config" ]] && ! grep -Fxq "BOOK_ENROLL_GUID=$guid" "$config"; then
    echo 'La cuenta asystec cambió. Verificá el destino antes de volver a vincularla.' >&2
    exit 1
fi
install -m 0644 index_peers.py "$base/index_peers.py"
printf 'BOOK_ENROLL_GUID=%s\n' "$guid" >"$config"
install -d /etc/systemd/system/asystec-book.service.d
printf '[Service]\nEnvironmentFile=%s\n' "$config" >/etc/systemd/system/asystec-book.service.d/enrollment.conf
cat >/etc/systemd/system/asystec-peer-index.service <<'UNIT'
[Unit]
Description=Export verified Asystec device IDs for installation enrollment
After=rustdesk-hbbs.service
[Service]
Type=oneshot
User=rustdesk
Group=desk-book
ExecStart=/usr/bin/python3 /opt/asystec-book/index_peers.py
RuntimeDirectory=asystec-enroll
RuntimeDirectoryMode=0750
RuntimeDirectoryPreserve=yes
UMask=0027
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateNetwork=true
InaccessiblePaths=/var/lib/rustdesk/id_ed25519
UNIT
cat >/etc/systemd/system/asystec-peer-index.timer <<'UNIT'
[Unit]
Description=Refresh Asystec installation enrollment verifiers
[Timer]
OnBootSec=5s
OnUnitActiveSec=30s
AccuracySec=3s
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl start asystec-peer-index.service
systemctl enable --now asystec-peer-index.timer
systemctl restart asystec-book
