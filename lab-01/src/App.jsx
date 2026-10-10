/**
 * Главный компонент страницы: хранит ввод и состояние интерфейса.
 * React вызывает функцию при отрисовке; возвращаемый JSX описывает нужный DOM.
 * Сеть вынесена в api.js, а случайное число вычисляется только на сервере.
 */
import { useRef, useState } from 'react';
import { requestRandom } from './api.js';

// Клиентская копия серверного ограничения для быстрой подсказки пользователю.
// Подчёркивания — разделители цифр в JS, значение остаётся обычным числом.
const LIMIT = 1_000_000_000;

export default function App() {
  // useState возвращает текущее значение и функцию его обновления.
  // Поля хранят строки: пустой ввод нельзя сразу превращать в число 0.
  const [min, setMin] = useState('1');
  const [max, setMax] = useState('100');
  // pending управляет блокировкой формы; null означает отсутствие результата;
  // пустая строка error означает отсутствие сообщения об ошибке.
  const [pending, setPending] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');
  // Ref сохраняется между отрисовками, но его изменение не обновляет DOM.
  // Это немедленный замок: защищает даже от двух submit до новой отрисовки.
  const inFlight = useRef(false);

  // Общий обработчик обоих полей. Старое число больше не относится к новому
  // диапазону, поэтому вместе с вводом очищаем результат и прежнюю ошибку.
  function changeValue(setValue, value) {
    setValue(value);
    setResult(null);
    setError('');
  }

  // Один обработчик submit обслуживает и кнопку, и Enter внутри формы.
  // async позволяет ожидать Promise от requestRandom без блокирования страницы.
  async function handleSubmit(event) {
    // Отменяем стандартную отправку HTML-формы с переходом на новую страницу.
    event.preventDefault();
    if (inFlight.current) return;
    setError('');
    setResult(null);

    // Сначала проверяем пустоту: Number('') равен 0 и скрыл бы ошибку ввода.
    if (!min.trim() || !max.trim()) {
      setError('Заполните оба поля диапазона.');
      return;
    }
    // Преобразование выполняется перед запросом, чтобы JSON содержал числа.
    // isInteger одновременно отклоняет дроби, NaN и бесконечности.
    const lower = Number(min);
    const upper = Number(max);
    if (!Number.isInteger(lower) || !Number.isInteger(upper)) {
      setError('Минимум и максимум должны быть целыми числами.');
      return;
    }
    // Модуль числа позволяет одной проверкой ограничить обе стороны диапазона.
    if (Math.abs(lower) > LIMIT || Math.abs(upper) > LIMIT) {
      setError('Границы должны быть от −1 000 000 000 до 1 000 000 000.');
      return;
    }
    if (lower > upper) {
      setError('Минимум не должен превышать максимум.');
      return;
    }

    // Блокируем только проверенную отправку. Ошибки ввода до этого места
    // завершаются return и вообще не создают сетевого запроса.
    inFlight.current = true;
    setPending(true);
    try {
      // После await получаем проверенный объект { min, max, value }.
      // Обновление state вызывает отрисовку результата через JSX ниже.
      setResult(await requestRandom(lower, upper));
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Не удалось получить результат.');
    } finally {
      // Выполняется и при успехе, и при исключении: форма не останется заблокированной.
      inFlight.current = false;
      setPending(false);
    }
  }

  return (
    <main className="card">
      <p className="caption">Лабораторная работа № 1 · Вариант 6</p>
      <h1>Генератор случайных чисел</h1>
      <p className="intro">Задайте диапазон целых чисел. Обе границы включаются в результат.</p>
      {/* noValidate отключает встроенные всплывающие сообщения браузера:
          проверки выполняем сами единообразно. Атрибуты полей сохраняют семантику.
          aria-busy сообщает вспомогательным технологиям о незавершённом действии. */}
      <form onSubmit={handleSubmit} noValidate aria-busy={pending}>
        <p id="range-hint" className="caption">Допустимые границы: от −1 000 000 000 до 1 000 000 000.</p>
        {/* fieldset группирует элементы, disabled блокирует все поля и кнопку.
            legend задаёт доступное название группы. */}
        <fieldset disabled={pending}>
          <legend>Диапазон</legend>
          {/* CSS Grid меняет число колонок через @media без изменения React-кода. */}
          <div className="range-fields">
            <div className="field">
              {/* htmlFor связан с id: подпись доступна диктору и фокусирует поле.
                  value + onChange образуют управляемое поле: источник данных — state.
                  aria-describedby связывает поле с подсказкой и текущей ошибкой. */}
              <label htmlFor="min">Минимум</label>
              <input id="min" name="min" type="number" required step="1" min={-LIMIT} max={LIMIT}
                value={min} onChange={event => changeValue(setMin, event.target.value)}
                aria-describedby={error ? 'range-hint form-error' : 'range-hint'} />
            </div>
            <div className="field">
              <label htmlFor="max">Максимум</label>
              <input id="max" name="max" type="number" required step="1" min={-LIMIT} max={LIMIT}
                value={max} onChange={event => changeValue(setMax, event.target.value)}
                aria-describedby={error ? 'range-hint form-error' : 'range-hint'} />
            </div>
          </div>
          {/* Тернарный оператор выбирает текст по состоянию запроса. */}
          <button type="submit">{pending ? 'Генерация…' : 'Сгенерировать'}</button>
        </fieldset>
      </form>
      {/* Постоянная область alert объявляет появившуюся ошибку целиком.
          React вставляет сообщение как текст, не исполняя HTML из ответа сервера. */}
      <p id="form-error" role="alert" className="error" aria-atomic="true">{error}</p>
      {/* polite просит объявлять изменения без прерывания текущей речи.
          Три варианта: ожидание / результат / инструкция до результата.
          Фрагмент <>...</> группирует JSX без дополнительного HTML-элемента. */}
      <section className="result" aria-live="polite" aria-atomic="true" aria-label="Результат генерации">
        {pending ? <p>Ожидаем ответ сервера…</p> : result ? <>
          <p className="result-label">Случайное число</p>
          <output>{result.value}</output>
          <p>Диапазон: от {result.min} до {result.max}</p>
        </> : <p>Введите диапазон и нажмите «Сгенерировать».</p>}
      </section>
    </main>
  );
}
