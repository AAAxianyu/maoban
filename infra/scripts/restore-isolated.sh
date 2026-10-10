#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${BACKUP_FILE:?Set BACKUP_FILE to a pg_dump custom archive}"
test -s "$BACKUP_FILE"
test -s "$BACKUP_FILE.sha256"
python3 - "$BACKUP_FILE" <<'PY'
import hashlib, re, sys
from pathlib import Path
archive = Path(sys.argv[1])
expected = Path(str(archive) + '.sha256').read_text().split()[0]
if not re.fullmatch(r'[0-9a-f]{64}', expected):
    raise SystemExit('Invalid checksum file')
with archive.open('rb') as source:
    digest = hashlib.sha256()
    for block in iter(lambda: source.read(1024 * 1024), b''):
        digest.update(block)
    actual = digest.hexdigest()
if actual != expected:
    raise SystemExit('Backup checksum mismatch; restore not started')
print('backup_checksum=verified')
PY
restore_name="miaoban-restore-$(date -u +%Y%m%d%H%M%S)"
# Separate container and private network namespace: never overwrite a running database.
docker run -d --network none --name "$restore_name" -e POSTGRES_USER=miaoban -e POSTGRES_PASSWORD=restore-isolated-only -e POSTGRES_DB=miaoban_restore postgres:18.3-alpine >/dev/null
for _ in {1..30}; do
  if docker exec "$restore_name" pg_isready -U miaoban -d miaoban_restore >/dev/null; then break; fi
  sleep 1
done
docker exec -i "$restore_name" pg_restore -U miaoban -d miaoban_restore --no-owner --no-acl --exit-on-error < "$BACKUP_FILE"
mismatch=$(docker exec "$restore_name" psql -U miaoban -d miaoban_restore -At -v ON_ERROR_STOP=1 -c \
  'SELECT count(*) FROM (SELECT w.space_id,w.user_id FROM wallets w LEFT JOIN ledger_entries l ON (w.space_id=l.space_id AND w.user_id=l.user_id) GROUP BY w.space_id,w.user_id,w.balance HAVING w.balance <> COALESCE(SUM(l.delta),0)) x;')
printf 'wallet_mismatch=%s\n' "$mismatch"
test "$mismatch" = 0
printf 'Restored in isolated container %s. Compare task/order data before cleanup; container retained.\n' "$restore_name"
