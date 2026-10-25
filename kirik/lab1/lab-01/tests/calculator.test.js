import test from 'node:test';
import assert from 'node:assert/strict';
import { calculate } from '../server/calculator.js';
import { app } from '../server/app.js';

test('Все операции, дробные и отрицательные числа', () => {
  for (const [a,b,operation,value] of [[1.5,2,'+',3.5],[-5,2,'-',-7],[-3,4,'*',-12],[7,2,'/',3.5]]) assert.equal(calculate({a,b,operation}).value,value);
});
test('Ошибки области определения и строгие типы', () => {
  for (const data of [null,[],{a:1,b:0,operation:'/'},{a:true,b:2,operation:'+'},{a:'2',b:2,operation:'+'},{a:Infinity,b:1,operation:'+'},{a:1,b:2,operation:'^'}]) assert.throws(() => calculate(data));
});
test('HTTP: JSON, валидация, health и страница', async () => {
  const server=app.listen(0,'127.0.0.1'); await new Promise(resolve=>server.once('listening',resolve));
  const url='http://127.0.0.1:'+server.address().port;
  try {
    assert.equal((await fetch(url+'/')).status,200);
    assert.equal((await fetch(url+'/api/health')).status,200);
    const send=data=>fetch(url+'/api/calculate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
    assert.equal((await (await send({a:10,b:4,operation:'/'})).json()).value,2.5);
    assert.equal((await send({a:1,b:0,operation:'/'})).status,400);
    assert.equal((await fetch(url+'/api/calculate',{method:'POST',body:'text'})).status,415);
  } finally { await new Promise(resolve=>server.close(resolve)); }
});
