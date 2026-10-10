"""Compare actual domain tables in development and an isolated restored database."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
container = sys.argv[1]
if not re.fullmatch(r'miaoban-restore-\d{14}', container):
    raise SystemExit('Only our isolated restore container is allowed')
tables = ['spaces', 'memberships', 'space_rule_versions', 'task_templates', 'task_versions', 'task_schedule_changes', 'member_rest_dates', 'daily_plans', 'task_instances', 'corrections', 'wallets', 'reward_entitlements', 'ledger_entries', 'rewards', 'wishes', 'redemptions', 'milestones', 'milestone_versions', 'room_contributions', 'room_unlocks', 'user_achievements', 'events', 'reactions', 'notifications', 'outbox', 'push_receipts']
# Every value stays in memory; evidence contains only counts/hashes, no secrets or notes.
checks = {}
for table in tables:
    sql = f"SELECT COALESCE(jsonb_agg(obj ORDER BY obj::text),'[]') FROM (SELECT to_jsonb(t) AS obj FROM {table} t) x;"
    source = subprocess.check_output(['docker', 'compose', '--env-file', '.env', '-f', 'infra/compose.yaml', 'exec', '-T', 'db', 'psql', '-U', 'miaoban', '-d', 'miaoban', '-At', '-v', 'ON_ERROR_STOP=1', '-c', sql], cwd=ROOT, text=True).strip()
    restored = subprocess.check_output(['docker', 'exec', container, 'psql', '-U', 'miaoban', '-d', 'miaoban_restore', '-At', '-v', 'ON_ERROR_STOP=1', '-c', sql], text=True).strip()
    assert source == restored, f'{table} differs'
    checks[table] = {'rows': len(json.loads(source)), 'sha256': hashlib.sha256(source.encode()).hexdigest(), 'exact_match': True}
proof = {'scope': 'isolated development backup, latest schema; not production', 'restore_container': container, 'checks': checks}
(ROOT / 'docs/verification/restore-comparison.json').write_text(json.dumps(proof, indent=2))
print(f'Exact domain comparison passed for {len(checks)} tables')
