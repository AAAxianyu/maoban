#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${CONFIG_FILE:?Set CONFIG_FILE}"
: "${COMPOSE_FILE:?Set COMPOSE_FILE}"
: "${PUBLIC_URL:?Set deployed HTTPS URL}"
result=0
curl --fail --silent --show-error --max-time 15 "$PUBLIC_URL/ready" || result=1
# Read-only checks. Do not log DB URL, credentials, push tokens or notification content.
if counts=$(docker compose --env-file "$CONFIG_FILE" -f "$COMPOSE_FILE" exec -T db psql -U miaoban -d miaoban -At -v ON_ERROR_STOP=1 -c \
"SELECT 'failed_push=' || count(*) FROM outbox WHERE status='failed'; SELECT 'configuration_missing=' || count(*) FROM outbox WHERE status='configuration_missing'; SELECT 'wallet_mismatch=' || count(*) FROM (SELECT w.space_id,w.user_id FROM wallets w LEFT JOIN ledger_entries l ON w.space_id=l.space_id AND w.user_id=l.user_id GROUP BY w.space_id,w.user_id,w.balance HAVING w.balance<>COALESCE(SUM(l.delta),0)) x;"
); then
  while IFS='=' read -r label count; do
    printf '%s=%s\n' "$label" "$count"
    if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then result=1; fi
  done <<< "$counts"
else
  result=1
fi
python3 - <<'PY' || result=1
from pathlib import Path
from datetime import datetime, timezone
import shutil, sys
root = Path('backups')
archives = [p for p in root.glob('miaoban-*.dump') if p.is_file() and not p.is_symlink()]
if not archives or datetime.now(timezone.utc).timestamp() - max(p.stat().st_mtime for p in archives) > 30*3600:
    print('backup_stale=true'); sys.exit(1)
free = shutil.disk_usage('.').free
print('disk_free_bytes=' + str(free))
if free < 2*1024**3: sys.exit(1)
PY
exit "$result"
