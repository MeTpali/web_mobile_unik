// Чистая предметная функция, не зависящая от HTTP или DOM.
export function calculate(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Ожидается объект');
  const { a, b, operation } = input;
  if (Object.keys(input).some(key => !['a', 'b', 'operation'].includes(key))) throw new Error('Неизвестные поля');
  if (![a, b].every(value => typeof value === 'number' && Number.isFinite(value) && Math.abs(value) <= 1e12)) throw new Error('Введите два конечных числа от −10¹² до 10¹²');
  if (!['+', '-', '*', '/'].includes(operation)) throw new Error('Неизвестная операция');
  if (operation === '/' && b === 0) throw new Error('Деление на ноль запрещено');
  const value = operation === '+' ? a+b : operation === '-' ? a-b : operation === '*' ? a*b : a/b;
  if (!Number.isFinite(value)) throw new Error('Результат не является конечным числом');
  return { a, b, operation, value };
}
