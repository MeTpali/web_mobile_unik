import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/calculation.dart';
import '../services/calculator_service.dart';

// Состояние и корреляция запросов находятся здесь; UI не разбирает JSON.
class CalculatorController extends ChangeNotifier {
  CalculatorController(this.service) {
    _subscription = service.messages.listen(_receive, onError: (Object e) => _fail(e.toString()));
  }
  final CalculatorService service;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  final List<Calculation> _history = [];
  List<Calculation> get history => List.unmodifiable(_history);
  bool connected = false, connecting = false;
  bool get waiting => _pending != null;
  String? error;
  Map<String, dynamic>? _pending;
  Timer? _timer;
  int _sequence = 0, _generation = 0;
  bool _disposed = false;

  Future<void> connect(String address) async {
    final uri = Uri.tryParse(address.trim());
    if (uri == null || !['ws', 'wss'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) {
      error = 'Введите ws://<IP-ПК>:8100/ws/calculate'; notifyListeners(); return;
    }
    disconnect(); final generation = _generation;
    connecting = true; notifyListeners();
    try {
      await service.connect(uri);
      if (_disposed || generation != _generation) return;
      connecting = false; connected = true; notifyListeners();
    } catch (e) { if (!_disposed && generation == _generation) _fail('Ошибка подключения: $e'); }
  }
  void calculate(String first, String second, String operation) {
    if (!connected || waiting) return;
    final a = double.tryParse(first.trim().replaceAll(',', '.'));
    final b = double.tryParse(second.trim().replaceAll(',', '.'));
    if (a == null || b == null || !a.isFinite || !b.isFinite || a.abs() > 1e12 || b.abs() > 1e12 || !['+', '-', '*', '/'].contains(operation)) {
      error = 'Введите два конечных числа от −10¹² до 10¹²'; notifyListeners(); return;
    }
    error = null;
    _pending = {'type': 'calculate', 'request_id': 'calc-${++_sequence}', 'a': a, 'b': b, 'operation': operation};
    _timer = Timer(const Duration(seconds: 10), () => _fail('Сервер не ответил за 10 секунд'));
    try { service.send(_pending!); } catch (e) { _fail(e.toString()); return; }
    notifyListeners();
  }
  void _receive(Map<String, dynamic> data) {
    if (_disposed || _pending == null || data['request_id'] != _pending!['request_id']) return;
    try {
      if (data['type'] == 'error') {
        error = (data['error'] as Map<String, dynamic>)['message'] as String;
      } else if (data['type'] == 'result') {
        final result = Calculation.fromJson(data);
        if (result.a != _pending!['a'] || result.b != _pending!['b'] || result.operation != _pending!['operation']) {
          throw const FormatException('Ответ не соответствует запросу');
        }
        _history.insert(0, result);
        if (_history.length > 10) _history.removeLast();
      } else { throw const FormatException('Неизвестный тип ответа'); }
      _timer?.cancel(); _pending = null; notifyListeners();
    } catch (e) { _fail(e.toString()); }
  }
  void _fail(String message) { if (_disposed) return; disconnect(); error = message; notifyListeners(); }
  void disconnect() {
    ++_generation; service.disconnect(); _timer?.cancel(); _pending = null;
    connecting = false; connected = false; error = null;
    if (!_disposed) notifyListeners();
  }
  @override
  void dispose() {
    _disposed = true; disconnect(); unawaited(_subscription.cancel()); service.dispose(); super.dispose();
  }
}
