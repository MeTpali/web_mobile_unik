import json
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.calculator import calculate
from app.protocol import handle_message

@pytest.mark.parametrize('a,b,op,expected',[(1.5,2,'+',3.5),(-5,2,'-',-7),(-3,4,'*',-12),(7,2,'/',3.5)])
def test_operations(a,b,op,expected):
    assert calculate(a,b,op)['value']==expected

@pytest.mark.parametrize('a,b,op',[(1,0,'/'),(True,1,'+'),('2',1,'+'),(1e13,1,'+'),(1,2,'^'),(float('inf'),1,'+')])
def test_validation(a,b,op):
    with pytest.raises(ValueError): calculate(a,b,op)

def test_protocol_and_socket_recovers():
    assert handle_message('NaN')['error']['code']=='INVALID_JSON'
    with TestClient(app) as c, c.websocket_connect('/ws/calculate') as ws:
        for b,kind in [(0,'error'),(2,'result')]:
            ws.send_json(dict(type='calculate',request_id='q',a=4,b=b,operation='/'))
            r=ws.receive_json(); assert r['type']==kind and r['request_id']=='q'
        assert r['value']==2
