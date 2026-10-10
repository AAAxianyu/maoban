"""Read real dev server facts around manually-operated Android offline/restart proof."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import httpx

with httpx.Client(base_url='http://127.0.0.1:8000/api/v1', timeout=15) as client:
    login = client.post('/auth/login', json={'username':'demo_b','password':'Demo-only-password-123'})
    login.raise_for_status()
    client.headers['Authorization']='Bearer '+login.json()['access_token']
    me=client.get('/auth/me').json()
    sid=next(s['id'] for s in me['spaces'] if s['name']=='隔离开发验收 9cb75208')
    snap=client.get(f'/spaces/{sid}/snapshot');snap.raise_for_status();snap=snap.json()
    ledger=client.get(f'/spaces/{sid}/ledger?limit=100').json()
    i=next(i for i in snap['daily']['instances'] if i['title']=='演示练习 1')
    data={'at':datetime.now(timezone.utc).isoformat(),'space_id':sid,'wallet':snap['wallet'],
          'instance':{k:i[k] for k in ['id','completed','version','points']},
          'ledger_count':len(ledger),'permanent_xp':snap['growth']['permanent_xp']}
    path=Path(__file__).resolve().parents[1]/'docs/verification/offline-proof.json'
    result=json.loads(path.read_text()) if path.exists() else {}
    result[sys.argv[1]]=data;path.write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps(data,ensure_ascii=False))
