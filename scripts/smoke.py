"""Real HTTP + WebSocket development smoke; demo accounts are deliberately isolated."""
import asyncio
import argparse
import json
import statistics
import time
from pathlib import Path
from uuid import uuid4
from urllib.parse import urlparse
import re

import httpx
import websockets

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base-url', default='http://127.0.0.1:8000')
parser.add_argument('--evidence-stem', default='http-smoke')
parser.add_argument('--scope', default='development, localhost Docker; no phones')
args = parser.parse_args()
address = urlparse(args.base_url)
if address.scheme != 'http' or address.hostname not in ('127.0.0.1', 'localhost') or address.port not in (8000, 18001) or address.path or address.username:
    parser.error('Only isolated local development or the dedicated cloud acceptance SSH tunnel is allowed')
if not re.fullmatch(r'[a-z0-9-]+', args.evidence_stem):
    parser.error('Evidence stem must be a plain filename')
BASE = args.base_url
evidence = root / 'docs/verification' / (args.evidence_stem + '.json')


def actor(username):
    c = httpx.Client(base_url=BASE+"/api/v1", timeout=15)
    r=c.post('/auth/login',json={'username':username,'password':'Demo-only-password-123'})
    r.raise_for_status()
    c.headers['Authorization']='Bearer '+r.json()['access_token']
    return c


def post(c,path,data=None):
    r=c.post(path,json=data,headers={'Idempotency-Key':str(uuid4())})
    r.raise_for_status()
    return r.json()


async def main():
    a,b=actor('demo_a'),actor('demo_b')
    ua,ub=a.get('/auth/me').json(),b.get('/auth/me').json()
    sid=post(a,'/spaces',{'name':'隔离开发验收 '+str(uuid4())[:8],'timezone':'America/Los_Angeles'})['id']
    prefix='/spaces/'+sid
    invitation=post(a,prefix+'/invitations')
    post(b,'/invitations/claim',{'token':invitation['token']})
    today=a.get(prefix).json()['today']
    for n,points in enumerate((10,5,15)):
        task=post(a,prefix+'/tasks',{'executor_id':ub['id'],'title':f'演示练习 {n+1}',
             'standard':'明确标记的开发验收','points':points,'tag':'c','starts_on':today})
        post(b,prefix+'/task-versions/'+task['proposal']['id']+'/decision',{'accepted':True})
    instances=b.get(prefix+'/daily').json()['instances']
    assert all(not i['required'] for i in instances),'Today additions must be optional'
    for i in instances:post(b,prefix+'/instances/'+i['id']+'/checkin',{'desired_state':True,'expected_version':0})
    assert b.get(prefix+'/wallet').json()['balance']==30
    goal=post(a,prefix+'/milestones',{'executor_id':ub['id'],'title':'开发验收三次任务','standard':'3 次有效 C 练习',
      'metric':'tasks','tag':'c','target':3,'starts_on':today,'ends_on':today,'reward_points':70})
    post(b,prefix+'/milestones/'+goal['id']+'/decision',{'accepted':True})
    assert b.get(prefix+'/wallet').json()['balance']==100
    reward=post(a,prefix+'/rewards',{'recipient_id':ub['id'],'title':'隔离测试饮料','description':'无生产兑现义务',
      'price':70,'stock':2,'published':True})
    order=post(b,prefix+'/rewards/'+reward['id']+'/redeem',{'confirmed_price':70})['order']
    assert b.get(prefix+'/wallet').json()['balance']==30
    post(b,prefix+'/orders/'+order['id']+'/command',{'action':'cancel','expected_version':1})
    post(b,prefix+'/orders/'+order['id']+'/command',{'action':'cancel','expected_version':1})
    assert b.get(prefix+'/wallet').json()['balance']==100
    fulfilled=post(b,prefix+'/rewards/'+reward['id']+'/redeem',{'confirmed_price':70})['order']
    post(a,prefix+'/orders/'+fulfilled['id']+'/command',{'action':'fulfill','expected_version':1})
    post(b,prefix+'/orders/'+fulfilled['id']+'/command',{'action':'confirm','expected_version':2})
    seq=a.get(prefix+'/snapshot').json()['snapshot_seq']
    samples=[]
    async with websockets.connect(BASE.replace('http','ws')+'/api/v1'+prefix+'/ws',
                                 additional_headers={'Authorization':a.headers['Authorization']}) as ws:
        await ws.send(json.dumps({'after_seq':seq}))
        for n in range(30):
            i=instances[0]
            started=time.perf_counter()
            result=await asyncio.to_thread(post,b,prefix+'/instances/'+i['id']+'/note',{'note':f'延迟样本 {n}', 'expected_version':n+1})
            while True:
                event=json.loads(await asyncio.wait_for(ws.recv(),timeout=5))['event']
                if event['entity_id']==i['id'] and event['entity_version']==result['version']:
                    samples.append((time.perf_counter()-started)*1000)
                    break
    exported=a.get(prefix+'/export').json()
    export_name = 'export-dev.json' if args.evidence_stem == 'http-smoke' else args.evidence_stem + '-export.json'
    (root/'docs/verification'/export_name).write_text(json.dumps(exported,ensure_ascii=False,indent=2))
    result={'environment':args.scope, 'space_id':sid,
      'http_core_flow':'passed', 'today_optional_balance':30,'stage_award_earned_balance':100,
      'redeem_70_balance':30,'cancel_once_restored_balance':100,'final_confirmed_order_balance':30,
      'websocket_samples_ms':samples,'websocket_http_start_to_event_p95_ms':sorted(samples)[28],
      'websocket_median_ms':statistics.median(samples), 'ac04_device_ui_latency':'NOT VERIFIED',
      'wallets':exported['wallets'], 'task_count':len(exported['task_instances']), 'order_count':len(exported['redemptions'])}
    evidence.write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k not in ('websocket_samples_ms','wallets')},ensure_ascii=False))
    a.close();b.close()


if __name__=='__main__':asyncio.run(main())
