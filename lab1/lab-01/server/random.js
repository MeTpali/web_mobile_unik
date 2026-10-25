/** Правила предметной области: проверка диапазона и случайная генерация.
 * Модуль работает в Node.js, не зависит от Express, HTTP или React.
 * node:crypto — встроенный модуль, отдельный npm-пакет для него не нужен.
 */
import { randomInt } from 'node:crypto';

// Наш предел приложения: числа и ширина диапазона точно представимы в JS
// и укладываются в ограничения randomInt. Это не предел самого JavaScript.
export const MIN_BOUND = -1_000_000_000;
export const MAX_BOUND = 1_000_000_000;

// Собственный тип позволяет HTTP-слою отличить ошибку ввода (400) от сбоя (500).
export class InvalidRangeError extends Error { }

/** Принимает объект { min, max }; возвращает { min, max, value }.
 * Проверки выполняются до генерации. Ошибка выбрасывается через throw,
 * а не возвращается вместо числа, чтобы её нельзя было принять за успех.
 */
export function generateRandom(input) {
  // typeof null равен 'object', массив тоже объект — исключаем оба явно.
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    throw new InvalidRangeError('Тело запроса должно быть объектом с полями min и max');
  }

  // Деструктуризация извлекает поля. Отсутствующее поле становится undefined.
  // isInteger не преобразует строки и boolean в числа, в отличие от Number().
  const { min, max } = input;
  if (!Number.isInteger(min) || !Number.isInteger(max)) {
    throw new InvalidRangeError('Минимум и максимум должны быть целыми числами');
  }
  if (min < MIN_BOUND || min > MAX_BOUND || max < MIN_BOUND || max > MAX_BOUND) {
    throw new InvalidRangeError('Границы должны быть от −1 000 000 000 до 1 000 000 000');
  }
  // Неверный порядок не исправляем автоматически: пользователь должен его увидеть.
  if (min > max) {
    throw new InvalidRangeError('Минимум не должен превышать максимум');
  }

  // У randomInt верхняя граница исключается; у нашего API — включается.
  // Равные границы дают детерминированный результат; повтор числа допустим.
  // Добавление 1 делает исходный max достижимым. randomInt избегает modulo bias.
  const value = min === max ? min : randomInt(min, max + 1);
  return { min, max, value };
}
