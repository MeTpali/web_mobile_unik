import 'package:flutter/material.dart';
import '../controllers/calculator_controller.dart';

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key, required this.createController});
  final CalculatorController Function() createController;
  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  late final CalculatorController controller = widget.createController();
  final address = TextEditingController(
      text: const String.fromEnvironment('WS_URL',
          defaultValue: 'ws://192.168.0.104:8100/ws/calculate'));
  final first = TextEditingController(text: '12.5'),
      second = TextEditingController(text: '2');
  String operation = '+';
  @override
  void dispose() {
    controller.dispose();
    address.dispose();
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Калькулятор')),
        body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                            controller: address,
                            decoration: const InputDecoration(
                                labelText: 'WebSocket сервера')),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: controller.connecting
                                ? null
                                : () => controller.connect(address.text),
                            child: Text(controller.connecting
                                ? 'Подключение…'
                                : 'Подключиться')),
                        OutlinedButton(
                            onPressed: controller.connected
                                ? controller.disconnect
                                : null,
                            child: const Text('Отключиться')),
                        Text(controller.connected
                            ? 'Подключено'
                            : 'Нет соединения'),
                        const SizedBox(height: 24),
                        TextField(
                            controller: first,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                                labelText: 'Первое число')),
                        const SizedBox(height: 12),
                        DropdownButton<String>(
                            value: operation,
                            isExpanded: true,
                            items: ['+', '-', '*', '/']
                                .map((op) => DropdownMenuItem(
                                    value: op, child: Text(op)))
                                .toList(),
                            onChanged: controller.waiting
                                ? null
                                : (value) =>
                                    setState(() => operation = value!)),
                        TextField(
                            controller: second,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                                labelText: 'Второе число')),
                        const SizedBox(height: 20),
                        FilledButton(
                            onPressed:
                                controller.connected && !controller.waiting
                                    ? () => controller.calculate(
                                        first.text, second.text, operation)
                                    : null,
                            child: const Text('Вычислить')),
                        if (controller.waiting) const LinearProgressIndicator(),
                        if (controller.error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(controller.error!,
                                  style: const TextStyle(color: Colors.red))),
                        const SizedBox(height: 20),
                        const Text('Последние вычисления',
                            style: TextStyle(fontSize: 22)),
                        for (final result in controller.history)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(result.toString())),
                      ]),
                )),
      );
}
