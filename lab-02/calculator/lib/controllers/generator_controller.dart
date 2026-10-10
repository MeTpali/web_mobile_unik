import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/number_range.dart';
import '../models/random_result.dart';
import '../services/random_service.dart';

enum GeneratorConnectionState { disconnected, connecting, connected }

/// Управляет действиями пользователя и состоянием генератора.
/// Сервис передаётся снаружи, поэтому логику можно проверять без сети.
class GeneratorController extends ChangeNotifier {
  GeneratorController(
    this._service, {
    this.responseTimeout = const Duration(seconds: 10),
  }) {
    _subscription = _service.events.listen(_onEvent);
  }

  final RandomService _service;
  final Duration responseTimeout;
  late final StreamSubscription<RandomServiceEvent> _subscription;
  GeneratorConnectionState _status = GeneratorConnectionState.disconnected;
  String? _error;
  final List<RandomResult> _history = [];
  String? _requestId;
  NumberRange? _pendingRange;
  Timer? _timer;
  int _sequence = 0;
  int _generation = 0;
  bool _disposed = false;

  GeneratorConnectionState get status => _status;
  String? get error => _error;
  bool get waiting => _requestId != null;
  List<RandomResult> get history => List.unmodifiable(_history);
  RandomResult? get latestResult => _history.firstOrNull;
  bool get canGenerate =>
      _status == GeneratorConnectionState.connected && !waiting;

  Future<void> connect(String address) async {
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
    final generation = _generation;
    _status = GeneratorConnectionState.connecting;
    notifyListeners();
    try {
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
    if (!canGenerate) return;
    final range = NumberRange(minimum, maximum);
    if (!range.isValid) {
      _error = 'Некорректный диапазон';
      notifyListeners();
      return;
    }
    _requestId = 'request-${++_sequence}';
    _pendingRange = range;
    _error = null;
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
    if (event is RandomConnectionLost) {
      _fail(event.message);
      return;
    }
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
      _history.insert(0, result);
      if (_history.length > 10) _history.removeLast();
    }
    _error = event.error;
    _clearRequest();
    notifyListeners();
  }

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
    unawaited(_subscription.cancel());
    _service.dispose();
    super.dispose();
  }
}
