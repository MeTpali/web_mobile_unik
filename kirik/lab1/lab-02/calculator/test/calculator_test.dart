import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:calculator/controllers/calculator_controller.dart';
import 'package:calculator/services/calculator_service.dart';

class FakeService implements CalculatorService {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? request;
  @override
  Stream<Map<String, dynamic>> get messages => events.stream;
  @override
  Future<void> connect(Uri uri) async {}
  @override
  void send(Map<String, dynamic> value) { request = value; }
  @override
  void disconnect() {}
  @override
  void dispose() { unawaited(events.close()); }
}
void main() {
  test('Корреляция, ошибка деления и следующий успешный результат', () async {
    final service = FakeService(); final c = CalculatorController(service);
    await c.connect('ws://localhost:8100/ws/calculate');
    c.calculate('1', '0', '/');
    service.events.add({'type':'result', 'request_id':'foreign', 'a':1, 'b':0, 'operation':'/', 'value':0});
    await Future<void>.delayed(Duration.zero); expect(c.waiting, true);
    service.events.add({'type':'error', 'request_id':service.request!['request_id'], 'error':{'message':'Деление на ноль'}});
    await Future<void>.delayed(Duration.zero); expect(c.connected, true); expect(c.error, 'Деление на ноль');
    c.calculate('1,5', '2', '+');
    service.events.add({...service.request!, 'type':'result', 'value':3.5});
    await Future<void>.delayed(Duration.zero); expect(c.history.single.value, 3.5); expect(c.waiting, false);
    c.dispose();
  });
}
