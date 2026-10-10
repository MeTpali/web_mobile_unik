import 'package:flutter/material.dart';
import '../controllers/generator_controller.dart';
import '../models/number_range.dart';
import '../models/random_result.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            )),
      );
}

class ConnectionCard extends StatelessWidget {
  const ConnectionCard(
      {super.key,
      required this.address,
      required this.status,
      required this.onConnect,
      required this.onDisconnect});
  final TextEditingController address;
  final GeneratorConnectionState status;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  @override
  Widget build(BuildContext context) {
    final connected = status == GeneratorConnectionState.connected;
    final connecting = status == GeneratorConnectionState.connecting;
    return SectionCard(children: [
      Row(children: [
        Icon(Icons.circle,
            size: 12, color: connected ? Colors.green : Colors.orange),
        const SizedBox(width: 8),
        Text(connected
            ? 'Подключено'
            : connecting
                ? 'Подключение…'
                : 'Нет подключения'),
      ]),
      const SizedBox(height: 16),
      TextField(
        controller: address,
        enabled: !connected && !connecting,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Адрес WebSocket'),
        onSubmitted: (_) => onConnect(),
      ),
      const SizedBox(height: 8),
      const Text('Укажите IP компьютера с Python-сервером. '
          'Телефон и компьютер должны быть в одной локальной сети.'),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: connected || connecting ? onDisconnect : onConnect,
        icon: Icon(connected || connecting ? Icons.link_off : Icons.link),
        label: Text(connected
            ? 'Отключиться'
            : connecting
                ? 'Отменить'
                : 'Подключиться'),
      ),
    ]);
  }
}

class RangeCard extends StatelessWidget {
  const RangeCard(
      {super.key,
      required this.minimum,
      required this.maximum,
      required this.formKey,
      required this.waiting,
      required this.canGenerate,
      required this.onGenerate});
  final TextEditingController minimum;
  final TextEditingController maximum;
  final GlobalKey<FormState> formKey;
  final bool waiting;
  final bool canGenerate;
  final VoidCallback onGenerate;
  @override
  Widget build(BuildContext context) {
    return SectionCard(children: [
      Text('Диапазон', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Обе границы включены. Допустимы отрицательные числа.'),
      const SizedBox(height: 16),
      Form(
          key: formKey,
          child: Column(children: [
            TextFormField(
              controller: minimum,
              validator: NumberRange.validateBound,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(labelText: 'Минимум'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: maximum,
              validator: (text) {
                return NumberRange.validateMaximum(
                  text,
                  minimum.text,
                );
              },
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(labelText: 'Максимум'),
            ),
          ])),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: canGenerate ? onGenerate : null,
        icon: waiting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.casino_outlined),
        label: Text(waiting ? 'Ожидание ответа…' : 'Сгенерировать'),
      ),
    ]);
  }
}

class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.result});
  final RandomResult? result;
  @override
  Widget build(BuildContext context) {
    return SectionCard(children: [
      const Text('Последний результат', textAlign: TextAlign.center),
      const SizedBox(height: 8),
      SelectableText(result == null ? '—' : '${result!.value}',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .displayMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 8),
      Text(
          result == null
              ? 'Подключитесь и задайте диапазон'
              : 'от ${result!.minimum} до ${result!.maximum}',
          textAlign: TextAlign.center),
    ]);
  }
}

class HistoryCard extends StatelessWidget {
  const HistoryCard({super.key, required this.history});
  final List<RandomResult> history;
  @override
  Widget build(BuildContext context) {
    return SectionCard(children: [
      Text('История · последние 10',
          style: Theme.of(context).textTheme.titleMedium),
      for (final item in history)
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${item.value}'),
            trailing: Text('${item.minimum} … ${item.maximum}')),
    ]);
  }
}
