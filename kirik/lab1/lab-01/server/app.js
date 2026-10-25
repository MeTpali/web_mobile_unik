import express from 'express';
import { fileURLToPath } from 'node:url';
import { calculate } from './calculator.js';
export const app = express();
app.get('/api/health', (_req, res) => res.json({status: 'ok'}));
app.post('/api/calculate', (req, res, next) => {
  if (!req.is('application/json')) return res.status(415).json({error: {code:'CONTENT_TYPE', message:'Ожидается application/json'}});
  next();
}, express.json({limit:'4kb', strict:false}), (req, res) => {
  try { res.set('Cache-Control','no-store').json(calculate(req.body)); }
  catch (error) { res.status(400).json({error:{code:'INVALID_OPERATION',message:error.message}}); }
});
app.use('/api', (_req,res) => res.status(404).json({error:{code:'NOT_FOUND',message:'Маршрут не найден'}}));
app.use(express.static(fileURLToPath(new URL('../public/', import.meta.url))));
app.use((error, _req, res, _next) => {
  const status = error.status === 400 ? 400 : error.status === 413 ? 413 : 500;
  res.status(status).json({error:{code:'REQUEST_ERROR',message:status === 500 ? 'Внутренняя ошибка сервера' : 'Неверный JSON или размер запроса'}});
});
