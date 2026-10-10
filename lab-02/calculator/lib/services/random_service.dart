import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/number_range.dart';
import '../models/random_result.dart';

/// Типизированные события протокола, без состояния экрана и истории.
sealed class RandomServiceEvent {}

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
    final generation = _generation;
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
      socket.pingInterval = const Duration(seconds: 15);
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
      rethrow;
    }
  }

  @override
  void generate(String requestId, NumberRange range) {
    final socket = _socket;
    if (socket == null) throw StateError('WebSocket is not connected');
    socket.add(jsonEncode({
      'type': 'generate',
      'request_id': requestId,
      'min': range.minimum,
      'max': range.maximum,
    }));
  }

  RandomResponse _decode(dynamic frame) {
    if (frame is! String) throw const FormatException();
    final data = jsonDecode(frame);
    if (data is! Map<String, dynamic>) throw const FormatException();
    final id = data['request_id'];
    if (id != null && id is! String) throw const FormatException();
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
    unawaited(_events.close());
  }
}
