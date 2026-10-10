"""Generate local credentials without overwriting existing configuration."""
import secrets
from pathlib import Path

root = Path(__file__).resolve().parents[1]
target = root / '.env'
if not target.exists():
    password = secrets.token_urlsafe(32)
    target.write_text(f'ENVIRONMENT=development\nPOSTGRES_PASSWORD={password}\n'
        f'DATABASE_URL=postgresql+psycopg://miaoban:{password}@127.0.0.1:55432/miaoban\n'
        'PUBLIC_URL=http://localhost:8000\nPUSH_PROVIDER=disabled\n')
    target.chmod(0o600)
    print('Created .env with generated local database credentials')
else:
    print('Existing .env preserved')
