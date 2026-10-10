#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${CONFIG_FILE:?Set CONFIG_FILE to a configured .env file}"
: "${COMPOSE_FILE:?Set COMPOSE_FILE to the deployment compose file}"
umask 077
mkdir -p backups
name="backups/miaoban-$(date -u +%Y%m%dT%H%M%SZ).dump"
docker compose --env-file "$CONFIG_FILE" -f "$COMPOSE_FILE" exec -T db pg_dump -U miaoban -d miaoban -Fc > "$name.partial"
test -s "$name.partial"
mv "$name.partial" "$name"
python3 - "$name" <<'PY'
import hashlib, sys
from pathlib import Path
p = Path(sys.argv[1])
digest = hashlib.sha256()
with p.open('rb') as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b''):
        digest.update(chunk)
Path(str(p) + '.sha256').write_text(digest.hexdigest() + '  ' + str(p) + '\n')
PY
python3 infra/scripts/retention.py --apply
printf '%s\n' "$name"
