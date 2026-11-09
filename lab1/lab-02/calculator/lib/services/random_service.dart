// Интерфейс сервиса и реализация WebSocket-транспорта. Управляет соединением, кодирует запросы,
// разбирает ответы и передаёт типизированные события без зависимости от Flutter. Сервис управляет
// WebSocket и JSON. Stream доставляет события, Future завершает асинхронный шаг; виджетам не нужно
// знать устройство транспорта.
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
  // Человекочитаемый статус последней/текущей операции, который экран показывает пользователю.
  final String message;
}

// Контракт обмена. Интерфейс не хранит историю и не сообщает UI
// через ChangeNotifier: такие задачи принадлежат контроллеру.
abstract interface class RandomService {
  Stream<RandomServiceEvent> get events;
  // Асинхронное подключение с тайм-аутом. Поколение запроса отличает текущую попытку от позднего
  // завершения старой.
  Future<void> connect(Uri address);
  void generate(String requestId, NumberRange range);
  // Закрывает сокет/подписку и делает старые callbacks устаревшими. unawaited помечает намеренное
  // завершение в фоне.
  void disconnect();
  // Освобождает подписки, таймеры и контроллеры ввода: закрытый экран не должен получать события и
  // удерживать ресурсы.
  void dispose();
}

class WebSocketRandomService implements RandomService {
  WebSocketRandomService(
      {this.connectionTimeout = const Duration(seconds: 10)});

  final Duration connectionTimeout;
  // broadcast допускает несколько слушателей. События не сохраняются:
  // контроллер подписывается до подключения.
  // Канал событий сервиса; broadcast разрешает нескольких слушателей. Канал закрывается при dispose.
  final _events = StreamController<RandomServiceEvent>.broadcast();
  // Текущее WebSocket-соединение; null обозначает отсутствие транспорта.
  WebSocket? _socket;
  // Сохраняем подписку, чтобы отменить её при закрытии и не получать события после уничтожения экрана.
  // Подписка на поток кадров. Сохраняется для отмены при disconnect/dispose.
  StreamSubscription<dynamic>? _subscription;
  // Счётчик поколений соединения. Увеличение делает callbacks прежнего подключения неактуальными.
  int _generation = 0;
  // Флаг завершения контроллера. Поздний callback не должен уведомлять уже уничтоженный экран.
  bool _disposed = false;

  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  Stream<RandomServiceEvent> get events => _events.stream;

  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Асинхронное подключение с тайм-аутом. Поколение запроса отличает текущую попытку от позднего
  // завершения старой.
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
      // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
      // её состояние.
      if (_disposed || generation != _generation) {
        unawaited(socket.close());
      }
    }, onError: (Object _) {}));
    try {
      final socket = await pending.timeout(connectionTimeout);
      // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
      // её состояние.
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
          // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
          // её состояние.
          if (generation != _generation) return;
          try {
            _events.add(_decode(frame));
          } on FormatException {
            _lost('Некорректный ответ сервера. Подключитесь снова');
          }
        },
        onError: (Object _) {
          // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
          // её состояние.
          if (generation == _generation) {
            _lost('Соединение с сервером потеряно');
          }
        },
        onDone: () {
          // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
          // её состояние.
          if (generation == _generation) {
            _lost('Сервер закрыл соединение. Подключитесь снова');
          }
        },
        cancelOnError: true,
      );
    } catch (_) {
      // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
      // её состояние.
      if (generation == _generation) disconnect();
      // Передаём исходное исключение контроллеру, который выберет
      // пользовательское сообщение об ошибке подключения.
      rethrow;
    }
  }

  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  void generate(String requestId, NumberRange range) {
    final socket = _socket;
    if (socket == null) throw StateError('WebSocket is not connected');
    // jsonEncode возвращает String, поэтому отправляется текстовый кадр.
    // Числа сохраняются как int: Python отклоняет строковые и дробные границы.
    // Кодируем данные в JSON-текст транспорта. Сериализация не заменяет проверку доменных значений.
    socket.add(jsonEncode({
      'type': 'generate',
      // Корреляция ответа с запросом: правильный JSON старого ожидания не должен завершать текущую операцию.
      'request_id': requestId,
      'min': range.minimum,
      'max': range.maximum,
    }));
  }

  // dynamic необходим на границе сокета: кадр может быть String или bytes.
  // Ниже последовательно сужаем типы, прежде чем создавать модель.
  RandomResponse _decode(dynamic frame) {
    if (frame is! String) throw const FormatException();
    // Разбираем JSON-кадр; типы/обязательные поля проверяются перед использованием.
    final data = jsonDecode(frame);
    if (data is! Map<String, dynamic>) throw const FormatException();
    // Корреляция ответа с запросом: правильный JSON старого ожидания не должен завершать текущую операцию.
    final id = data['request_id'];
    if (id != null && id is! String) throw const FormatException();
    // Прикладная ошибка — допустимый ответ, она не разрывает соединение.
    // Серверная ошибка относится к вычислению/протоколу, а не обязательно к разрыву сокета. Сохраняем
    // понятное сообщение.
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

  // Сообщает о потере транспорта. Это отдельное событие, не ошибка валидации пользовательского ввода.
  void _lost(String message) {
    if (_disposed) return;
    disconnect();
    _events.add(RandomConnectionLost(message));
  }

  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Закрывает сокет/подписку и делает старые callbacks устаревшими. unawaited помечает намеренное
  // завершение в фоне.
  void disconnect() {
    // Сначала инвалидируем старые callbacks, затем отменяем подписку
    // и закрываем сокет. ?. безопасен, если соединение не было установлено.
    // Смена поколения сразу делает callbacks старого подключения устаревшими, даже если cancel/close ещё
    // завершаются в фоне.
    ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_socket?.close());
    _socket = null;
  }

  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Освобождает подписки, таймеры и контроллеры ввода: закрытый экран не должен получать события и
  // удерживать ресурсы.
  void dispose() {
    _disposed = true;
    disconnect();
    // Закрытие StreamController освобождает сам источник событий.
    unawaited(_events.close());
  }
}
