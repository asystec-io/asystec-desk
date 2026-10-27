#!/usr/bin/env bash
# RustDesk Server OSS, pinned official release. Run as root on Ubuntu amd64.
set -euo pipefail

VERSION=1.1.16
PUBLIC_IP=184.197.59.221
ARCHIVE_SHA256=0565c41affe6c3f409b0bddfaf5a24ccbf3f64f5f8e3fec250b69a0d5f6bdbcf
RELEASE_DIR="/opt/rustdesk/releases/$VERSION"
STATE_DIR=/var/lib/rustdesk

test "$(id -u)" = 0
test "$(uname -m)" = x86_64
command -v python3 >/dev/null
command -v curl >/dev/null
command -v ufw >/dev/null

install -d -m 0755 "$RELEASE_DIR" /var/cache/rustdesk
curl --fail --location --retry 3 \
  "https://github.com/rustdesk/rustdesk-server/releases/download/$VERSION/rustdesk-server-linux-amd64.zip" \
  -o "/var/cache/rustdesk/rustdesk-server-$VERSION.zip"
printf '%s  %s\n' "$ARCHIVE_SHA256" "/var/cache/rustdesk/rustdesk-server-$VERSION.zip" | sha256sum --check -

python3 - "$VERSION" "$RELEASE_DIR" <<'PY'
import pathlib
import sys
import zipfile
version, destination = sys.argv[1:]
with zipfile.ZipFile(f"/var/cache/rustdesk/rustdesk-server-{version}.zip") as archive:
    for executable in ("hbbs", "hbbr"):
        matches = [name for name in archive.namelist()
                   if pathlib.PurePosixPath(name).name == executable]
        if len(matches) != 1:
            raise RuntimeError(f"Unexpected archive members for {executable}: {matches}")
        path = pathlib.Path(destination, executable)
        path.write_bytes(archive.read(matches[0]))
        path.chmod(0o755)
PY

if ! id rustdesk >/dev/null 2>&1; then
  useradd --system --user-group --home-dir "$STATE_DIR" --shell /usr/sbin/nologin rustdesk
fi
install -d -o rustdesk -g rustdesk -m 0750 "$STATE_DIR"

# Preserve any prior unit configuration. Never replace server keys or database.
BACKUP_DIR="/var/backups/rustdesk/install-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$BACKUP_DIR"
for unit in rustdesk-hbbs rustdesk-hbbr; do
  if test -f "/etc/systemd/system/$unit.service"; then
    cp -a "/etc/systemd/system/$unit.service" "$BACKUP_DIR/"
  fi
done
ufw status verbose > "$BACKUP_DIR/ufw-before.txt"

cat > /etc/systemd/system/rustdesk-hbbs.service <<EOF
[Unit]
Description=RustDesk OSS ID and rendezvous server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=rustdesk
Group=rustdesk
WorkingDirectory=$STATE_DIR
ExecStart=$RELEASE_DIR/hbbs -r $PUBLIC_IP:21117 -k _
Restart=always
RestartSec=5
LimitNOFILE=65536
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$STATE_DIR
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/rustdesk-hbbr.service <<EOF
[Unit]
Description=RustDesk OSS relay server
Wants=network-online.target rustdesk-hbbs.service
After=network-online.target rustdesk-hbbs.service

[Service]
Type=simple
User=rustdesk
Group=rustdesk
WorkingDirectory=$STATE_DIR
ExecStart=$RELEASE_DIR/hbbr -k _
Restart=always
RestartSec=5
LimitNOFILE=65536
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$STATE_DIR
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
EOF

# Keep SSH reachable before enabling the host firewall.
ufw allow 22/tcp comment 'SSH administration'
ufw allow 21115:21117/tcp comment 'RustDesk native clients'
ufw allow 21116/udp comment 'RustDesk registration'
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

systemctl daemon-reload
systemctl enable --now rustdesk-hbbs.service
for attempt in $(seq 1 20); do
  test -s "$STATE_DIR/id_ed25519.pub" && break
  sleep 1
done
test -s "$STATE_DIR/id_ed25519.pub"
systemctl enable --now rustdesk-hbbr.service
systemctl is-active rustdesk-hbbs.service rustdesk-hbbr.service
systemctl is-enabled rustdesk-hbbs.service rustdesk-hbbr.service

{
  date -u +%Y-%m-%dT%H:%M:%SZ
  printf 'RustDesk Server OSS %s\nPublic IP: %s\nArchive SHA256: %s\n' "$VERSION" "$PUBLIC_IP" "$ARCHIVE_SHA256"
  sha256sum "$RELEASE_DIR/hbbs" "$RELEASE_DIR/hbbr"
} > /opt/rustdesk/install-receipt.txt

printf '\nPublic client key:\n'
cat "$STATE_DIR/id_ed25519.pub"
printf '\n'
ufw status verbose
