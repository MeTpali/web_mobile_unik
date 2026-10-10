import 'package:flutter/material.dart';
import '../controllers/generator_controller.dart';
import 'generator_cards.dart';

class GeneratorPage extends StatefulWidget {
  const GeneratorPage({super.key, required this.createController});
  final GeneratorController Function() createController;
  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends State<GeneratorPage> {
  late final GeneratorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.createController();
  }

  final _address = TextEditingController(
      text: const String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://192.168.1.10:8000/ws/random',
  ));
  final _minimum = TextEditingController(text: '1');
  final _maximum = TextEditingController(text: '100');
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    _address.dispose();
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  void _generate() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _controller.generate(
        int.parse(_minimum.text.trim()), int.parse(_maximum.text.trim()));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(title: const Text('Генератор чисел')),
            body: SafeArea(
                child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Лабораторная № 2 · Вариант 6',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 16),
                      ConnectionCard(
                          address: _address,
                          status: _controller.status,
                          onConnect: () => _controller.connect(_address.text),
                          onDisconnect: _controller.disconnect),
                      RangeCard(
                          minimum: _minimum,
                          maximum: _maximum,
                          formKey: _form,
                          waiting: _controller.waiting,
                          canGenerate: _controller.canGenerate,
                          onGenerate: _generate),
                      if (_controller.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(_controller.error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ),
                      ResultCard(result: _controller.latestResult),
                      if (_controller.history.isNotEmpty)
                        HistoryCard(history: _controller.history),
                    ]),
              )),
            )),
          );
        },
      );
}
