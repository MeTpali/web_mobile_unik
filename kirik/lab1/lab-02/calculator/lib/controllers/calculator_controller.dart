// Контроллер Flutter: ввод, состояние, request_id и история. Контроллер связывает UI и сервисы.
// Сначала данные проверяются/сохраняются, затем выполняется обмен; сигналы уведомляют UI о новом
// состоянии. UI не должен дублировать сетевой протокол.
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/calculation.dart';
import '../services/calculator_service.dart';

// Состояние и корреляция запросов находятся здесь; UI не разбирает JSON.
class CalculatorController extends ChangeNotifier {
  // Внедряем сервис через конструктор. Можно подставить транспорт-заглушку в тесте; подписка создаётся
  // один раз.
  CalculatorController(this.service) {
    _subscription = service.messages.listen(_receive, onError: (Object e) => _fail(e.toString()));
  }
  final CalculatorService service;
  // Сохраняем подписку, чтобы отменить её при закрытии и не получать события после уничтожения экрана.
  // Подписка на поток кадров. Сохраняется для отмены при disconnect/dispose.
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  // Недавние успешные результаты. Снаружи отдаётся неизменяемое представление, чтобы UI не менял
  // состояние в обход контроллера.
  final List<Calculation> _history = [];
  // Возвращаем read-only копию списка: UI может читать историю, но не менять её в обход notifyListeners.
  List<Calculation> get history => List.unmodifiable(_history);
  bool connected = false, connecting = false;
  bool get waiting => _pending != null;
  String? error;
  // Ожидаемая команда или null. Содержит request_id и параметры, которые проверяются при ответе.
  Map<String, dynamic>? _pending;
  // Таймер ожидания ответа. Он должен отменяться при завершении команды или отключении.
  Timer? _timer;
  // Счётчик request_id внутри запуска, чтобы отличать последовательные пользовательские команды.
  int _sequence = 0, _generation = 0;
  // Флаг завершения контроллера. Поздний callback не должен уведомлять уже уничтоженный экран.
  bool _disposed = false;

  // Асинхронное подключение с тайм-аутом. Поколение запроса отличает текущую попытку от позднего
  // завершения старой.
  Future<void> connect(String address) async {
    // Разбираем адрес без исключения. Схема ws/wss, хост и запрет userInfo/fragment проверяются отдельно.
    final uri = Uri.tryParse(address.trim());
    if (uri == null || !['ws', 'wss'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) {
      // Сообщаем слушателям об изменении состояния. Это инициирует перестроение UI, а не дополнительный
      // запрос.
      error = 'Введите ws://<IP-ПК>:8100/ws/calculate'; notifyListeners(); return;
    }
    disconnect(); final generation = _generation;
    // Сообщаем слушателям об изменении состояния. Это инициирует перестроение UI, а не дополнительный
    // запрос.
    connecting = true; notifyListeners();
    try {
      await service.connect(uri);
      // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
      // её состояние.
      if (_disposed || generation != _generation) return;
      // Сообщаем слушателям об изменении состояния. Это инициирует перестроение UI, а не дополнительный
      // запрос.
      connecting = false; connected = true; notifyListeners();
    // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
    // её состояние.
    } catch (e) { if (!_disposed && generation == _generation) _fail('Ошибка подключения: $e'); }
  }
  // Запуск одной команды: проверяем соединение/ввод, фиксируем request_id и параметры, ставим таймер,
  // затем передаём JSON сервису. Результат придёт асинхронно.
  void calculate(String first, String second, String operation) {
    // Ранний выход предотвращает запрос без сокета и второй одновременный запрос, когда первый ещё ждёт
    // ответа.
    if (!connected || waiting) return;
    // Пробуем превратить строку в число, заменяя десятичную запятую. При ошибке возвращается null, который
    // проверяется до отправки.
    final a = double.tryParse(first.trim().replaceAll(',', '.'));
    // Пробуем превратить строку в число, заменяя десятичную запятую. При ошибке возвращается null, который
    // проверяется до отправки.
    final b = double.tryParse(second.trim().replaceAll(',', '.'));
    // Отклоняем неправильный формат, NaN/Infinity, чрезмерную величину и неизвестный знак до передачи
    // JSON.
    if (a == null || b == null || !a.isFinite || !b.isFinite || a.abs() > 1e12 || b.abs() > 1e12 || !['+', '-', '*', '/'].contains(operation)) {
      // Сообщаем слушателям об изменении состояния. Это инициирует перестроение UI, а не дополнительный
      // запрос.
      error = 'Введите два конечных числа от −10¹² до 10¹²'; notifyListeners(); return;
    }
    error = null;
    // Корреляция ответа с запросом: правильный JSON старого ожидания не должен завершать текущую операцию.
    _pending = {'type': 'calculate', 'request_id': 'calc-${++_sequence}', 'a': a, 'b': b, 'operation': operation};
    // Таймер ограничивает ожидание. При ответе/disconnect отменяется, иначе поздний timeout испортил бы
    // уже успешное состояние.
    _timer = Timer(const Duration(seconds: 10), () => _fail('Сервер не ответил за 10 секунд'));
    try { service.send(_pending!); } catch (e) { _fail(e.toString()); return; }
    // Сообщаем слушателям об изменении состояния. Это инициирует перестроение UI, а не дополнительный
    // запрос.
    notifyListeners();
  }
  // Проверяет request_id и содержимое ответа, завершает ожидание. Старый ответ не должен завершить новый
  // запрос.
  void _receive(Map<String, dynamic> data) {
    // Корреляция ответа с запросом: правильный JSON старого ожидания не должен завершать текущую операцию.
    if (_disposed || _pending == null || data['request_id'] != _pending!['request_id']) return;
    try {
      // Серверная ошибка относится к вычислению/протоколу, а не обязательно к разрыву сокета. Сохраняем
      // понятное сообщение.
      if (data['type'] == 'error') {
        error = (data['error'] as Map<String, dynamic>)['message'] as String;
      } else if (data['type'] == 'result') {
        // Типизированная модель проверяет структуру ответа. Затем сравниваем операнды/операцию с ожидаемым
        // запросом, а не доверяем только request_id.
        final result = Calculation.fromJson(data);
        if (result.a != _pending!['a'] || result.b != _pending!['b'] || result.operation != _pending!['operation']) {
          throw const FormatException('Ответ не соответствует запросу');
        }
        // Добавляем успешный результат в начало, чтобы последняя операция была первой в истории.
        _history.insert(0, result);
        // Оставляем только десять последних результатов: история не растёт бесконечно в памяти.
        if (_history.length > 10) _history.removeLast();
      } else { throw const FormatException('Неизвестный тип ответа'); }
      // Сообщаем слушателям об изменении состояния. Это инициирует перестроение UI, а не дополнительный
      // запрос.
      _timer?.cancel(); _pending = null; notifyListeners();
    } catch (e) { _fail(e.toString()); }
  }
  // Сбрасывает ожидание и сохраняет понятную ошибку. notifyListeners сообщает экрану, что её нужно
  // показать.
  void _fail(String message) { if (_disposed) return; disconnect(); error = message; notifyListeners(); }
  // Закрывает сокет/подписку и делает старые callbacks устаревшими. unawaited помечает намеренное
  // завершение в фоне.
  void disconnect() {
    // Смена поколения сразу делает callbacks старого подключения устаревшими, даже если cancel/close ещё
    // завершаются в фоне.
    ++_generation; service.disconnect(); _timer?.cancel(); _pending = null;
    connecting = false; connected = false; error = null;
    // Сообщаем слушателям об изменении состояния. Это инициирует перестроение UI, а не дополнительный
    // запрос.
    if (!_disposed) notifyListeners();
  }
  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Освобождает подписки, таймеры и контроллеры ввода: закрытый экран не должен получать события и
  // удерживать ресурсы.
  void dispose() {
    _disposed = true; disconnect(); unawaited(_subscription.cancel()); service.dispose(); super.dispose();
  }
}
