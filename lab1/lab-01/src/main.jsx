/** Точка входа браузерного приложения, подключённая из index.html.
 * React описывает интерфейс; react-dom связывает его с DOM браузера.
 * Импорт CSS обрабатывает Vite: в сборке стили попадут в отдельный ресурс.
 */
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
import './styles.css';

// Находим HTML-контейнер и передаём React управление его содержимым.
// StrictMode включает дополнительные проверки в разработке (в том числе
// повторные вызовы рендера). Он не означает двойную отправку формы пользователем.
createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
