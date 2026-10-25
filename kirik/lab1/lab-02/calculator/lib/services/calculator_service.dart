import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Контроллер знает интерфейс сервиса; тест может подставить реализацию без сети.
abstract class CalculatorService {
  Stream<Map<String, dynamic>> get messages;
  Future<void> connect(Uri uri);
  void send(Map<String, dynamic> request);
  void disconnect();
  void dispose();
}

class WebSocketCalculatorService implements CalculatorService {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  int _generation = 0;
  @override
  Stream<Map<String, dynamic>> get messages => _events.stream;
  @override
  Future<void> connect(Uri uri) async {
    disconnect();
    final generation = _generation;
    final socket = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Не удалось подключиться'));
    if (generation != _generation) { unawaited(socket.close()); return; }
    _socket = socket;
    _subscription = socket.listen((dynamic frame) {
      try {
        if (frame is! String) throw const FormatException('Ожидается текстовый JSON');
        _events.add(jsonDecode(frame) as Map<String, dynamic>);
      } catch (error) { _events.addError(error); }
    }, onError: (Object error) => _events.addError(error),
      onDone: () { if (generation == _generation) _events.addError(StateError('Соединение закрыто')); });
  }
  @override
  void send(Map<String, dynamic> request) {
    if (_socket == null) throw StateError('Нет соединения');
    _socket!.add(jsonEncode(request));
  }
  @override
  void disconnect() {
    ++_generation;
    unawaited(_subscription?.cancel()); _subscription = null;
    unawaited(_socket?.close()); _socket = null;
  }
  @override
  void dispose() { disconnect(); unawaited(_events.close()); }
}
