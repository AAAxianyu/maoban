"""Real development API restart and durable WebSocket cursor evidence; no UI latency claim."""
import asyncio
import json
import subprocess
from pathlib import Path
from uuid import uuid4

import httpx
import websockets

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ['docker', 'compose', '--env-file', '.env', '-f', 'infra/compose.yaml']


async def main():
    with httpx.Client(base_url='http://127.0.0.1:8000/api/v1', timeout=15) as a, httpx.Client(base_url='http://127.0.0.1:8000/api/v1', timeout=15) as b:
        for client, username in [(a, 'demo_a'), (b, 'demo_b')]:
            r = client.post('/auth/login', json={'username': username, 'password': 'Demo-only-password-123'})
            r.raise_for_status()
            client.headers['Authorization'] = 'Bearer ' + r.json()['access_token']
        sid = json.loads((ROOT / 'docs/verification/http-smoke.json').read_text())['space_id']
        prefix = '/spaces/' + sid
        before = b.get(prefix + '/snapshot').json()
        cursor = before['snapshot_seq']
        instance = next(i for i in before['daily']['instances'] if i['title'] == '演示练习 1')
        url = 'ws://127.0.0.1:8000/api/v1' + prefix + '/ws'
        async with websockets.connect(url, additional_headers={'Authorization': a.headers['Authorization']}) as ws:
            await ws.send(json.dumps({'after_seq': cursor}))
        r = b.post(prefix + '/instances/' + instance['id'] + '/note', json={'note': '开发重连验收：断开时写入，API 重启后恢复游标', 'expected_version': instance['version']}, headers={'Idempotency-Key': str(uuid4())})
        r.raise_for_status()
        expected_seq = b.get(prefix + '/snapshot').json()['snapshot_seq']
        subprocess.run(COMPOSE + ['restart', 'api'], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        for _ in range(40):
            try:
                if httpx.get('http://127.0.0.1:8000/ready', timeout=1).status_code == 200:
                    break
            except httpx.HTTPError:
                pass
            await asyncio.sleep(.5)
        else:
            raise RuntimeError('API did not recover')
        async with websockets.connect(url, additional_headers={'Authorization': a.headers['Authorization']}) as ws:
            await ws.send(json.dumps({'after_seq': cursor}))
            message = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            assert message['event']['seq'] == expected_seq
            assert message['event']['entity_id'] == instance['id']
        async with websockets.connect(url, additional_headers={'Authorization': a.headers['Authorization']}) as ws:
            await ws.send(json.dumps({'after_seq': expected_seq}))
            try:
                await asyncio.wait_for(ws.recv(), timeout=1)
            except asyncio.TimeoutError:
                pass
            else:
                raise AssertionError('Already acknowledged event replayed')
        after = b.get(prefix + '/snapshot').json()
        assert before['wallet'] == after['wallet']
        assert before['growth']['permanent_xp'] == after['growth']['permanent_xp']
        proof = {'scope': 'localhost development PostgreSQL/API restart, not phone UI timing', 'space_id': sid, 'cursor_before': cursor, 'replayed_seq': expected_seq, 'acknowledged_cursor_no_replay': True, 'wallet_unchanged': True, 'permanent_xp_unchanged': True}
        (ROOT / 'docs/verification/reconnect-proof.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2))
        print(json.dumps(proof, ensure_ascii=False))


if __name__ == '__main__':
    asyncio.run(main())
