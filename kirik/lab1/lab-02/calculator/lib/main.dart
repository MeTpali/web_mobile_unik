import 'package:flutter/material.dart';
import 'controllers/calculator_controller.dart';
import 'services/calculator_service.dart';
import 'ui/calculator_page.dart';

void main() => runApp(const CalculatorApp());

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});
  @override
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
