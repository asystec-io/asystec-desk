#!/usr/bin/env bash
# Run as root on the Asystec Desk Lightsail instance, from the uploaded libreta directory.
set -euo pipefail
cd "$(dirname "$0")"
ip=184.197.59.221
base=/opt/asystec-book
acme="$base/acme/bin/certbot"
test -x "$acme"
id desk-book >/dev/null 2>&1 || useradd --system --home /var/lib/asystec-book --shell /usr/sbin/nologin desk-book
install -d -m 0755 "$base" /var/www/asystec-acme
install -d -m 0700 -o desk-book -g desk-book /var/lib/asystec-book
install -m 0644 service.py requirements.txt "$base/"
python3 -m venv "$base/venv"
"$base/venv/bin/pip" -q install -r "$base/requirements.txt"
cat >/etc/systemd/system/asystec-book.service <<'UNIT'
[Unit]
Description=Asystec Desk personal address book
After=network.target
[Service]
User=desk-book
Group=desk-book
WorkingDirectory=/opt/asystec-book
Environment=BOOK_DB=/var/lib/asystec-book/libreta.sqlite3
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/opt/asystec-book/venv/bin/waitress-serve --listen=127.0.0.1:8787 --threads=1 --max-request-body-size=2097152 --call service:create_app
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/asystec-book
UMask=0077
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now asystec-book
systemctl restart asystec-book
ufw allow proto tcp from 0.0.0.0/0 to any port 80
ufw allow proto tcp from 0.0.0.0/0 to any port 443
cat >/etc/nginx/conf.d/asystec-book-http.conf <<'NGINX'
server {
    listen 80;
    server_name 184.197.59.221;
    location ^~ /.well-known/acme-challenge/ { root /var/www/asystec-acme; }
    location / { return 404; }
}
NGINX
nginx -t && systemctl reload nginx
install -d /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nnginx -t && systemctl reload nginx\n' >/etc/letsencrypt/renewal-hooks/deploy/asystec-nginx
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/asystec-nginx
"$acme" certonly --non-interactive --agree-tos --register-unsafely-without-email --preferred-profile shortlived --webroot -w /var/www/asystec-acme --ip-address "$ip" --cert-name asystec-book --keep-until-expiring
cat >/etc/nginx/conf.d/asystec-book-tls.conf <<'NGINX'
limit_req_zone $binary_remote_addr zone=book_login:1m rate=5r/m;
limit_req_zone $binary_remote_addr zone=book_signup:1m rate=1r/m;
server {
    listen 443 ssl default_server;
    server_name 184.197.59.221;
    ssl_certificate /etc/letsencrypt/live/asystec-book/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/asystec-book/privkey.pem;
    client_max_body_size 2m;
    location = /api/asystec/register {
        client_max_body_size 4k;
        limit_req zone=book_signup burst=3 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:8787;
    }
    location = /api/login {
        limit_req zone=book_login burst=5 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:8787;
    }
    location /api/ { proxy_pass http://127.0.0.1:8787; }
    location / { return 404; }
}
NGINX
nginx -t && systemctl reload nginx
cat >/etc/systemd/system/asystec-book-renew.service <<'UNIT'
[Unit]
Description=Renew Asystec Desk IP certificate
[Service]
Type=oneshot
ExecStart=/opt/asystec-book/acme/bin/certbot renew --cert-name asystec-book --quiet
UNIT
cat >/etc/systemd/system/asystec-book-renew.timer <<'UNIT'
[Unit]
Description=Check Asystec Desk certificate twice daily
[Timer]
OnCalendar=*-*-* 02,14:00:00
RandomizedDelaySec=30m
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now asystec-book-renew.timer
curl --fail --silent --resolve "$ip:443:127.0.0.1" "https://$ip/api/login-options"
systemctl is-active asystec-book asystec-book-renew.timer rustdesk-hbbs rustdesk-hbbr
