// Проверка реального Flutter/WebSocket на телефоне без flutter_tester для Linux.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:calculator/main.dart' as application;
import 'package:calculator/controllers/calculator_controller.dart';
import 'package:calculator/services/calculator_service.dart';

Future<void> until(bool Function() done) async {
  final limit = DateTime.now().add(const Duration(seconds: 15));
  while (!done() && DateTime.now().isBefore(limit)) {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  if (!done()) throw StateError('Тайм-аут проверки');
}

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const application.CalculatorApp());
  final controller = CalculatorController(WebSocketCalculatorService());
  final log = <String>[];
  final home = Platform.environment['HOME'] ?? '/home/defaultuser';
  final file = File('$home/.local/share/ru.kirik/calculator/verification.json');
  try {
    await controller.connect(const String.fromEnvironment('WS_URL', defaultValue: 'ws://192.168.0.104:8100/ws/calculate'));
    require(controller.connected, 'Не подключился WebSocket: ${controller.error}');
    for (final sample in <List<Object>>[
      ['12,5', '2', '+', 14.5], ['-5', '2', '-', -7],
      ['-3', '4', '*', -12], ['7', '2', '/', 3.5],
    ]) {
      controller.calculate(sample[0] as String, sample[1] as String, sample[2] as String);
      await until(() => !controller.waiting);
      require(controller.error == null && controller.history.first.value == sample[3], 'Неверный результат: $sample');
      log.add(controller.history.first.toString());
    }
    controller.calculate('1', '0', '/');
    await until(() => !controller.waiting);
    require(controller.error != null && controller.connected, 'Деление на ноль должно сохранять соединение');
    log.add('PASS division by zero; connection remains open');
    controller.calculate('', '2', '+');
    require(controller.error != null && !controller.waiting, 'Пустой ввод должен отклоняться');
    for (var i = 0; i < 12; i++) {
      controller.calculate('$i', '2', '+');
      await until(() => !controller.waiting);
      require(controller.error == null && controller.history.first.value == i + 2, 'Не восстановился после ошибки');
    }
    require(controller.history.length == 10, 'История должна быть ограничена 10 записями');
    controller.disconnect();
    require(!controller.connected, 'Соединение не закрыто');
    await controller.connect(const String.fromEnvironment('WS_URL', defaultValue: 'ws://192.168.0.104:8100/ws/calculate'));
    require(controller.connected, 'Переподключение не выполнено');
    controller.calculate('20', '4', '/');
    await until(() => !controller.waiting);
    require(controller.error == null && controller.history.first.value == 5, 'Не работает после переподключения');
    log.add('PASS validation, history limit, error recovery, reconnect');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'passed': true, 'checks': log}), flush: true);
    debugPrint('PASS Aurora calculator: ${log.join('; ')}');
  } catch (error, stack) {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'passed': false, 'error': '$error', 'stack': '$stack'}), flush: true);
    debugPrint('FAIL Aurora calculator: $error');
  } finally {
    controller.dispose();
  }
}
