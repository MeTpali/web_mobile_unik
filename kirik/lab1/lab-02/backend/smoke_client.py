"""Проверка калькулятора по настоящему WebSocket."""
import argparse, asyncio, json
from websockets.asyncio.client import connect
async def main(url):
    async with connect(url, open_timeout=5) as ws:
        for i,(a,b,op,value) in enumerate([(2,3,'+',5),(7,2,'/',3.5),(1,0,'/',None),(-3,2,'*',-6)]):
            await ws.send(json.dumps(dict(type='calculate',request_id=str(i),a=a,b=b,operation=op)))
            result=json.loads(await asyncio.wait_for(ws.recv(),5))
            assert result['request_id']==str(i)
            assert result['type']=='error' if value is None else result['value']==value
            print(result)
    print('PASS WebSocket calculator')
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--url',default='ws://127.0.0.1:8100/ws/calculate')
    asyncio.run(main(p.parse_args().url))
