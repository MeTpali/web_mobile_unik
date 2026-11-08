// Модель или интерфейс Flutter. Импорты подключают зависимости; основной код выполняет одну роль в
// цепочке приложения.
import 'package:flutter/material.dart';
import 'controllers/calculator_controller.dart';
import 'services/calculator_service.dart';
import 'ui/calculator_page.dart';

// Точка входа процесса: создаёт приложение и зависимости, передаёт их интерфейсу, запускает цикл
// событий.
// Flutter монтирует корневой виджет и начинает отрисовку. Сетевые зависимости создаются внутри
// приложения по предусмотренной фабрике.
void main() => runApp(const CalculatorApp());

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});
  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Возвращает дерево Flutter для текущего состояния. Повторный build обновляет представление; сеть и
  // вычисления остаются вне виджетов.
  Widget build(BuildContext context) => MaterialApp(
        title: 'Калькулятор',
        theme: ThemeData(
            colorSchemeSeed: const Color(0xff203931),
            brightness: Brightness.light,
            useMaterial3: true),
        home: CalculatorPage(
            createController: () =>
                CalculatorController(WebSocketCalculatorService())),
      );
}
