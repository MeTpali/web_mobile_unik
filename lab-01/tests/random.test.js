/** Модульные тесты предметной логики без HTTP и браузера.
 * node:test запускает сценарии, assert/strict выбрасывает ошибку при несоответствии.
 * Проверяем свойства результата, а не конкретное непредсказуемое число.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateRandom, InvalidRangeError } from '../server/random.js';

test('результат — целое число внутри включённых границ', () => {
  // Положительный, отрицательный, смешанный и полный диапазоны.
  // 1e9 — экспоненциальная запись 1 000 000 000. Повторы допустимы;
  // 100 выборок не доказывают равномерность распределения статистически.
  for (const [min, max] of [[1, 100], [-10, -1], [-10, 10], [-1e9, 1e9]]) {
    for (let i = 0; i < 100; i++) {
      const result = generateRandom({ min, max });
      // equal проверяет строгое равенство, ok — истинность условия.
      assert.equal(result.min, min);
      assert.equal(result.max, max);
      assert.ok(Number.isInteger(result.value));
      assert.ok(result.value >= min && result.value <= max);
    }
  }
});

// Для вырожденного диапазона ответ известен точно: deepEqual сравнивает весь объект.
test('одинаковые границы, включая предельные, возвращают единственное число', () => {
  for (const value of [0, 7, -1e9, 1e9]) {
    assert.deepEqual(generateRandom({ min: value, max: value }), { min: value, max: value, value });
  }
});

// Здесь можно проверить NaN/Infinity/undefined напрямую, даже если JSON
// не умеет представлять их самостоятельными числовыми значениями.
test('невалидные значения не преобразуются и отклоняются', () => {
  for (const input of [undefined, null, [], 1, {}, { min: 1 },
    { min: 2, max: 1 }, { min: 0.5, max: 2 }, { min: 0, max: 2.5 },
    { min: -1e9 - 1, max: 0 }, { min: 0, max: 1e9 + 1 },
    { min: '1', max: 2 }, { min: null, max: 2 }, { min: false, max: 2 },
    { min: NaN, max: 2 }, { min: 0, max: Infinity }]) {
    // Передаём функцию, чтобы assert сам вызвал её и проверил тип исключения.
    assert.throws(() => generateRandom(input), InvalidRangeError);
  }
});
