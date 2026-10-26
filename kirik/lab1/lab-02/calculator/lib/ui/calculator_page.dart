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
  final first = TextEditingController(text: '12.5');
  final second = TextEditingController(text: '2');
  String operation = '+';

  @override
  void dispose() {
    controller.dispose();
    address.dispose();
    first.dispose();
    second.dispose();
    super.dispose();
  }

  // Настройка транспорта не занимает место на рабочем экране калькулятора.
  Future<void> showConnection() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Подключение', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: address,
                    keyboardType: TextInputType.url,
                    decoration:
                        const InputDecoration(labelText: 'Адрес сервера'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: controller.connecting
                        ? null
                        : () => controller.connect(address.text),
                    child: Text(controller.connecting
                        ? 'Подключение…'
                        : 'Подключиться'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed:
                        controller.connected ? controller.disconnect : null,
                    child: const Text('Отключиться'),
                  ),
                  if (controller.error != null)
                    Text(controller.error!,
                        style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget numberField(String label, TextEditingController input) => TextField(
        controller: input,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: const TextStyle(fontSize: 28),
        decoration: InputDecoration(labelText: label, filled: true),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Scaffold(
          backgroundColor: const Color(0xfff7f5ee),
          appBar: AppBar(
            backgroundColor: const Color(0xfff7f5ee),
            title: const Text('Калькулятор'),
            actions: [
              IconButton(
                tooltip: 'Подключение',
                onPressed: showConnection,
                icon: Icon(controller.connected ? Icons.wifi : Icons.wifi_off),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('СЧИТАЕМ ПО ПОРЯДКУ',
                  style: TextStyle(letterSpacing: 2, fontSize: 12)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xff203931),
                  borderRadius: BorderRadius.only(
                      topRight: Radius.circular(32),
                      bottomLeft: Radius.circular(32)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Последний результат',
                        style: TextStyle(color: Color(0xffc6d7c9))),
                    const SizedBox(height: 12),
                    Text(
                      controller.history.isEmpty
                          ? '—'
                          : controller.history.first.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 30),
                    ),
                    if (controller.waiting)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              numberField('01 · Первое число', first),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final op in ['+', '-', '*', '/'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Center(
                              child: Text(op,
                                  style: const TextStyle(fontSize: 24))),
                          showCheckmark: false,
                          selected: operation == op,
                          onSelected: controller.waiting
                              ? null
                              : (_) => setState(() => operation = op),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              numberField('02 · Второе число', second),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: controller.connected && !controller.waiting
                    ? () =>
                        controller.calculate(first.text, second.text, operation)
                    : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Получить результат')),
              ),
              if (!controller.connected)
                TextButton(
                    onPressed: showConnection,
                    child: const Text('Настроить подключение')),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(controller.error!,
                      style: const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 28),
              const Text('Лента вычислений', style: TextStyle(fontSize: 22)),
              if (controller.history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Здесь появятся ваши вычисления'),
                ),
              for (final result in controller.history)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(result.toString()),
                ),
            ],
          ),
        ),
      );
}
