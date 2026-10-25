import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calculator/app.dart';
import 'package:calculator/controllers/generator_controller.dart';
import 'package:calculator/services/random_service.dart';

void main() {
  testWidgets('Начальный экран на узком устройстве', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    expect(find.text('Нет подключения'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byWidgetPredicate((widget) => widget is FilledButton))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  test('WebSocket: результат, ошибка, восстановление и переподключение',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((frame) {
        final data = jsonDecode(frame as String) as Map<String, dynamic>;
        socket.add(jsonEncode(data['min'] == 7
            ? {
                'type': 'error',
                'request_id': data['request_id'],
                'error': {'message': 'Ошибка сервера'},
              }
            : {
                'type': 'result',
                'request_id': data['request_id'],
                'value': data['min'],
                'min': data['min'],
                'max': data['max'],
              }));
      });
    });
    final client = GeneratorController(WebSocketRandomService());
    addTearDown(() async {
      client.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('Нет ответа');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    final url = 'ws://127.0.0.1:${server.port}/ws/random';
    await client.connect(url);
    expect(client.status, GeneratorConnectionState.connected);
    client.generate(-5, -5);
    await waitFor(() => !client.waiting);
    expect(client.history.first.value, -5);
    client.generate(7, 10);
    await waitFor(() => !client.waiting);
    expect(client.error, 'Ошибка сервера');
    client.generate(1, 100);
    await waitFor(() => !client.waiting);
    expect(client.error, isNull);
    await sockets.last.close();
    await waitFor(() => client.status == GeneratorConnectionState.disconnected);
    await client.connect(url);
    client.generate(42, 42);
    await waitFor(() => !client.waiting);
    expect(client.history.first.value, 42);
  });
}
