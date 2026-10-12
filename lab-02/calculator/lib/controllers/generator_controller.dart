// Контроллер отделяет действия пользователя от виджетов и WebSocket.
// dart:async нужен для Timer, StreamSubscription и unawaited.
// ChangeNotifier сообщает UI, что состояние изменилось.
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/number_range.dart';
import '../models/random_result.dart';
import '../services/random_service.dart';

// Перечисление исключает опечатки, возможные со строковыми статусами.
enum GeneratorConnectionState { disconnected, connecting, connected }

/// Управляет действиями пользователя и состоянием генератора.
/// Сервис передаётся снаружи, поэтому логику можно проверять без сети.
class GeneratorController extends ChangeNotifier {
  GeneratorController(
    this._service, {
    this.responseTimeout = const Duration(seconds: 10),
  }) {
    // Подписка создаётся один раз и живёт до dispose контроллера.
    _subscription = _service.events.listen(_onEvent);
  }

  // Зависимость имеет тип интерфейса: вместо реальной сети в тесте
  // можно передать FakeRandomService с теми же методами.
  final RandomService _service;
  final Duration responseTimeout;
  late final StreamSubscription<RandomServiceEvent> _subscription;
  GeneratorConnectionState _status = GeneratorConnectionState.disconnected;
  String? _error;
  final List<RandomResult> _history = [];
  // Ненулевой ID одновременно обозначает наличие активного запроса.
  // Диапазон сохраняем на момент отправки для проверки ответа.
  String? _requestId;
  NumberRange? _pendingRange;
  Timer? _timer;
  int _sequence = 0;
  // Номер попытки подключения защищает от позднего завершения старого Future.
  int _generation = 0;
  bool _disposed = false;

  // Снаружи доступны только геттеры. UI не должен изменять состояние
  // напрямую; List.unmodifiable защищает историю от внешнего изменения.
  GeneratorConnectionState get status => _status;
  String? get error => _error;
  bool get waiting => _requestId != null;
  List<RandomResult> get history => List.unmodifiable(_history);
  RandomResult? get latestResult => _history.firstOrNull;
  bool get canGenerate =>
      _status == GeneratorConnectionState.connected && !waiting;

  Future<void> connect(String address) async {
    // URI разбирается до обращения к сети. Адрес обязан содержать ws/wss
    // и имя сервера; логин в URL и фрагмент #... здесь не используются.
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !['ws', 'wss'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      _error = 'Введите адрес вида ws://192.168.1.10:8000/ws/random';
      notifyListeners();
      return;
    }
    disconnect();
    // Сохраняем номер текущей попытки. disconnect увеличивает его,
    // поэтому завершение отменённой попытки больше не обновит UI.
    final generation = _generation;
    _status = GeneratorConnectionState.connecting;
    notifyListeners();
    try {
      // await освобождает поток UI на время подключения; это не sleep.
      await _service.connect(uri);
      if (_disposed || generation != _generation) return;
      _status = GeneratorConnectionState.connected;
      notifyListeners();
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _fail('Не удалось подключиться. Проверьте адрес, сеть и запуск сервера');
    }
  }

  void generate(int minimum, int maximum) {
    // Пока нет соединения или уже ожидается ответ, повторное нажатие
    // не отправляет второй запрос. Контроллер защищён независимо от кнопки.
    if (!canGenerate) return;
    final range = NumberRange(minimum, maximum);
    if (!range.isValid) {
      _error = 'Некорректный диапазон';
      notifyListeners();
      return;
    }
    // ID уникален в пределах жизни контроллера. Сервер возвращает его
    // без изменения, но не использует для устранения повторной генерации.
    _requestId = 'request-${++_sequence}';
    _pendingRange = range;
    _error = null;
    // Это тайм-аут ответа на запрос, а не установки соединения.
    // После него старый запрос автоматически не повторяем.
    _timer = Timer(responseTimeout, () {
      _fail(
          'Сервер не ответил за ${responseTimeout.inSeconds} секунд. Подключитесь снова');
    });
    try {
      _service.generate(_requestId!, range);
    } catch (_) {
      _fail('Не удалось отправить запрос. Подключитесь снова');
      return;
    }
    notifyListeners();
  }

  void _onEvent(RandomServiceEvent event) {
    if (_disposed) return;
    // Потеря транспорта отличается от прикладной ошибки сервера:
    // при result/error сокет может оставаться исправным.
    if (event is RandomConnectionLost) {
      _fail(event.message);
      return;
    }
    // Чужой или уже неактуальный ID не должен завершать текущий запрос.
    if (event is! RandomResponse || !waiting || event.requestId != _requestId) {
      return;
    }
    final result = event.result;
    if (result != null) {
      if (result.minimum != _pendingRange!.minimum ||
          result.maximum != _pendingRange!.maximum) {
        _fail('Ответ сервера не соответствует запрошенному диапазону');
        return;
      }
      // Новые результаты находятся в начале; память ограничена 10 записями.
      _history.insert(0, result);
      if (_history.length > 10) _history.removeLast();
    }
    _error = event.error;
    _clearRequest();
    notifyListeners();
  }

  // Завершаем ожидание независимо от исхода, отменяя таймер.
  void _clearRequest() {
    _timer?.cancel();
    _timer = null;
    _requestId = null;
    _pendingRange = null;
  }

  void _fail(String message) {
    disconnect();
    _error = message;
    notifyListeners();
  }

  // Отключение сбрасывает сетевое состояние, но оставляет историю сеанса.
  void disconnect() {
    ++_generation;
    _service.disconnect();
    _clearRequest();
    _error = null;
    _status = GeneratorConnectionState.disconnected;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _clearRequest();
    // dispose синхронный, поэтому Future отмены не ожидаем.
    // Флаг _disposed предотвращает обновления уже уничтоженного контроллера.
    unawaited(_subscription.cancel());
    _service.dispose();
    super.dispose();
  }
}
