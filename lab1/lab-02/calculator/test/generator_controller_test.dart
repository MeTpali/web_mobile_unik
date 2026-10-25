import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:calculator/controllers/generator_controller.dart';
import 'package:calculator/models/number_range.dart';
import 'package:calculator/models/random_result.dart';
import 'package:calculator/services/random_service.dart';

class FakeRandomService implements RandomService {
  final messages = StreamController<RandomServiceEvent>.broadcast(sync: true);
  int requests = 0;
  String? lastId;
  NumberRange? lastRange;
  @override
  Stream<RandomServiceEvent> get events => messages.stream;
  @override
  Future<void> connect(Uri address) async {}
  @override
  void generate(String requestId, NumberRange range) {
    requests++;
    lastId = requestId;
    lastRange = range;
  }

  void reply({String? id}) => messages.add(RandomResponse(
        id ?? lastId,
        result: RandomResult(lastRange!.minimum, lastRange!),
      ));
  @override
  void disconnect() {}
  @override
  void dispose() {
    unawaited(messages.close());
  }
}

void main() {
  late FakeRandomService service;
  late GeneratorController controller;
  setUp(() {
    service = FakeRandomService();
    controller = GeneratorController(service);
  });
  tearDown(() => controller.dispose());

  test('Некорректный диапазон не отправляется; повторный запрос блокируется',
      () async {
    await controller.connect('ws://localhost/ws/random');
    controller.generate(10, 1);
    expect(service.requests, 0);
    controller.generate(1, 10);
    controller.generate(2, 10);
    expect(service.requests, 1);
    service.reply(id: 'чужой-id');
    expect(controller.waiting, isTrue);
    expect(controller.history, isEmpty);
    service.reply();
    expect(controller.waiting, isFalse);
    expect(controller.latestResult!.value, 1);
  });

  test('История ограничена десятью результатами и защищена от изменения',
      () async {
    await controller.connect('ws://localhost/ws/random');
    for (var i = 0; i < 12; i++) {
      controller.generate(i, i);
      service.reply();
    }
    expect(controller.history.length, 10);
    expect(controller.latestResult!.value, 11);
    expect(() => controller.history.clear(), throwsUnsupportedError);
  });

  test('Ответ с другим диапазоном отклоняется', () async {
    await controller.connect('ws://localhost/ws/random');
    controller.generate(1, 10);
    service.messages.add(RandomResponse(service.lastId,
        result: const RandomResult(42, NumberRange(42, 42))));
    expect(controller.status, GeneratorConnectionState.disconnected);
    expect(controller.history, isEmpty);
    expect(controller.error, contains('не соответствует'));
  });

  test('Тайм-аут снимает ожидание и отключает соединение', () async {
    controller.dispose();
    service = FakeRandomService();
    controller = GeneratorController(service,
        responseTimeout: const Duration(milliseconds: 5));
    await controller.connect('ws://localhost/ws/random');
    controller.generate(1, 10);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.waiting, isFalse);
    expect(controller.status, GeneratorConnectionState.disconnected);
    expect(controller.error, contains('Сервер не ответил'));
  });
}
