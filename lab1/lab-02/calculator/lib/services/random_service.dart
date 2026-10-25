// Сетевой слой не импортирует Flutter: он занимается только транспортом
// и протоколом. dart:io предоставляет нативный WebSocket (не Flutter Web),
// dart:convert — JSON, dart:async — поток событий и Future.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/number_range.dart';
import '../models/random_result.dart';

/// Типизированные события протокола, без состояния экрана и истории.
// sealed ограничивает набор наследников этой библиотекой. Контроллер
// различает тип события, вместо разбора нетипизированного JSON.
sealed class RandomServiceEvent {}

// Ответ сервера содержит результат либо сообщение прикладной ошибки.
// Nullable ID соответствует контракту сервера для некорректных запросов.
class RandomResponse extends RandomServiceEvent {
  RandomResponse(this.requestId, {this.result, this.error});
  final String? requestId;
  final RandomResult? result;
  final String? error;
}

class RandomConnectionLost extends RandomServiceEvent {
  RandomConnectionLost(this.message);
  final String message;
}

// Контракт обмена. Интерфейс не хранит историю и не сообщает UI
// через ChangeNotifier: такие задачи принадлежат контроллеру.
abstract interface class RandomService {
  Stream<RandomServiceEvent> get events;
  Future<void> connect(Uri address);
  void generate(String requestId, NumberRange range);
  void disconnect();
  void dispose();
}

class WebSocketRandomService implements RandomService {
  WebSocketRandomService(
      {this.connectionTimeout = const Duration(seconds: 10)});

  final Duration connectionTimeout;
  // broadcast допускает несколько слушателей. События не сохраняются:
  // контроллер подписывается до подключения.
  final _events = StreamController<RandomServiceEvent>.broadcast();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  int _generation = 0;
  bool _disposed = false;

  @override
  Stream<RandomServiceEvent> get events => _events.stream;

  @override
  Future<void> connect(Uri address) async {
    disconnect();
    // Каждое disconnect меняет поколение соединения. Поздние callbacks
    // от старого сокета не могут влиять на новую попытку.
    final generation = _generation;
    // connect выполняет HTTP Upgrade handshake. Отдельно отслеживаем
    // исходный Future: timeout сам по себе не отменяет операцию подключения.
    final pending = WebSocket.connect(address.toString());
    // Отмена и тайм-аут не отменяют handshake: поздний сокет закрываем.
    unawaited(pending.then((socket) {
      if (_disposed || generation != _generation) {
        unawaited(socket.close());
      }
    }, onError: (Object _) {}));
    try {
      final socket = await pending.timeout(connectionTimeout);
      if (_disposed || generation != _generation) return;
      _socket = socket;
      // Транспортный ping/pong выявляет неотвечающее соединение.
      // Это не дополнительный JSON-запрос к генератору.
      socket.pingInterval = const Duration(seconds: 15);
      // В отличие от HTTP одного соединения хватает для многих запросов.
      // listen получает кадры; onError и onDone обрабатывают разные
      // способы завершения потока. Ошибка формата также закрывает сокет.
      _subscription = socket.listen(
        (frame) {
          if (generation != _generation) return;
          try {
            _events.add(_decode(frame));
          } on FormatException {
            _lost('Некорректный ответ сервера. Подключитесь снова');
          }
        },
        onError: (Object _) {
          if (generation == _generation) {
            _lost('Соединение с сервером потеряно');
          }
        },
        onDone: () {
          if (generation == _generation) {
            _lost('Сервер закрыл соединение. Подключитесь снова');
          }
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (generation == _generation) disconnect();
      // Передаём исходное исключение контроллеру, который выберет
      // пользовательское сообщение об ошибке подключения.
      rethrow;
    }
  }

  @override
  void generate(String requestId, NumberRange range) {
    final socket = _socket;
    if (socket == null) throw StateError('WebSocket is not connected');
    // jsonEncode возвращает String, поэтому отправляется текстовый кадр.
    // Числа сохраняются как int: Python отклоняет строковые и дробные границы.
    socket.add(jsonEncode({
      'type': 'generate',
      'request_id': requestId,
      'min': range.minimum,
      'max': range.maximum,
    }));
  }

  // dynamic необходим на границе сокета: кадр может быть String или bytes.
  // Ниже последовательно сужаем типы, прежде чем создавать модель.
  RandomResponse _decode(dynamic frame) {
    if (frame is! String) throw const FormatException();
    final data = jsonDecode(frame);
    if (data is! Map<String, dynamic>) throw const FormatException();
    final id = data['request_id'];
    if (id != null && id is! String) throw const FormatException();
    // Прикладная ошибка — допустимый ответ, она не разрывает соединение.
    if (data['type'] == 'error') {
      final details = data['error'];
      if (details is! Map || details['message'] is! String) {
        throw const FormatException();
      }
      return RandomResponse(id as String?, error: details['message'] as String);
    }
    if (data['type'] != 'result') throw const FormatException();
    final value = data['value'];
    final minimum = data['min'];
    final maximum = data['max'];
    if (value is! int || minimum is! int || maximum is! int) {
      throw const FormatException();
    }
    // Даже успешный тип result не гарантирует корректности данных.
    // Проверяем целые числа, ограничения и попадание значения в диапазон.
    final range = NumberRange(minimum, maximum);
    if (!range.isValid || value < minimum || value > maximum) {
      throw const FormatException();
    }
    return RandomResponse(id as String?, result: RandomResult(value, range));
  }

  void _lost(String message) {
    if (_disposed) return;
    disconnect();
    _events.add(RandomConnectionLost(message));
  }

  @override
  void disconnect() {
    // Сначала инвалидируем старые callbacks, затем отменяем подписку
    // и закрываем сокет. ?. безопасен, если соединение не было установлено.
    ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_socket?.close());
    _socket = null;
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    // Закрытие StreamController освобождает сам источник событий.
    unawaited(_events.close());
  }
}
