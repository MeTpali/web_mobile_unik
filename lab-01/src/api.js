/** Сетевой слой клиента. Не зависит от React и потому тестируется отдельно.
 * Возвращает Promise с результатом либо отклоняет его с понятной Error.message.
 * HTTP, JSON и проверка ответа скрыты от компонента App.
 */
const TIMEOUT_MS = 10_000; // Миллисекунды: 10 секунд на запрос и чтение ответа.

export async function requestRandom(min, max) {
  // Отдельный контроллер на каждый запрос: отмена не затронет следующую попытку.
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    let response;
    try {
      // Относительный URL использует адрес открытой страницы: это важно на телефоне.
      // В разработке /api перенаправляет Vite; после сборки отвечает Express.
      response = await fetch('/api/random', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ min, max }), // Объект JS преобразуется в текст JSON.
        signal: controller.signal,
      });
    } catch (error) {
      // Отмену передаём наружу: общий catch ниже сформирует сообщение тайм-аута.
      if (controller.signal.aborted) throw error;
      throw new Error('Не удалось связаться с сервером. Проверьте подключение и повторите попытку.');
    }

    let data;
    try {
      // Чтение тела тоже асинхронно; сервер может вернуть не JSON, например HTML.
      data = await response.json();
    } catch (error) {
      if (controller.signal.aborted) throw error;
      throw new Error('Сервер вернул некорректный ответ. Попробуйте ещё раз.');
    }

    // fetch не отклоняет Promise только из-за HTTP 400/500; статус проверяем сами.
    // ok истинен для статусов 200–299. ?. безопасен при null/отсутствующих полях.
    if (!response.ok) {
      const message = data?.error?.message;
      throw new Error(typeof message === 'string' && message.trim()
        ? message
        : `Ошибка сервера (HTTP ${response.status}). Попробуйте ещё раз.`);
    }

    // Даже HTTP 200 недостаточно: проверяем структуру, диапазон и целочисленность.
    // Числовая строка не принимается вместо числа. Старой/чужой паре границ не доверяем.
    if (data?.min !== min || data?.max !== max || !Number.isInteger(data?.value)
      || data.value < min || data.value > max) {
      throw new Error('Сервер вернул некорректный результат. Попробуйте ещё раз.');
    }
    return data;
  } catch (error) {
    if (controller.signal.aborted) {
      throw new Error('Сервер не ответил за 10 секунд. Попробуйте ещё раз.');
    }
    throw error;
  } finally {
    // Таймер больше не нужен после любого исхода. Отмена fetch не гарантирует,
    // что сервер прекратил вычисление: она прекращает ожидание на клиенте.
    clearTimeout(timeout);
  }
}
