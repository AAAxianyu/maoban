#!/usr/bin/env bash
set -euo pipefail
: "${MIAOBAN_ROOT:?Set the dedicated deployment directory}"
"$MIAOBAN_ROOT/tools/certbot/bin/certbot" renew --non-interactive \
  --config-dir "$MIAOBAN_ROOT/tls" --work-dir "$MIAOBAN_ROOT/tls-work" \
  --logs-dir "$MIAOBAN_ROOT/tls-logs"
nginx -t
systemctl reload nginx
: "${MIAOBAN_IP:?Set the certificate IP address}"
openssl x509 -in "$MIAOBAN_ROOT/tls/live/$MIAOBAN_IP/fullchain.pem" \
  -checkend 86400 -noout
