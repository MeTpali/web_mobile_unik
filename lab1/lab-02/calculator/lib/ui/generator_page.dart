// Экран связывает виджеты со состоянием контроллера. Он не создаёт
// WebSocket и не разбирает JSON. Локальное состояние — поля ввода
// и жизненный цикл объектов, принадлежащих конкретному экрану.
import 'package:flutter/material.dart';
import '../controllers/generator_controller.dart';
import 'generator_cards.dart';

// StatefulWidget нужен для initState/dispose и сохранения полей
// при повторных build. Сам виджет — неизменяемая конфигурация экрана.
class GeneratorPage extends StatefulWidget {
  const GeneratorPage({super.key, required this.createController});
  // Фабрика передана из app.dart: экран не зависит от реализации сервиса.
  final GeneratorController Function() createController;
  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends State<GeneratorPage> {
  // late: значение назначается в initState, когда widget уже доступен.
  // final: этот экран использует один контроллер всю свою жизнь.
  late final GeneratorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.createController();
  }

  // TextEditingController сохраняет текст и позицию курсора.
  // String.fromEnvironment читает --dart-define=WS_URL при сборке,
  // а не переменные окружения телефона во время запуска.
  final _address = TextEditingController(
      text: const String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://192.168.1.10:8000/ws/random',
  ));
  final _minimum = TextEditingController(text: '1');
  final _maximum = TextEditingController(text: '100');
  // GlobalKey даёт доступ к FormState для проверки сразу всех полей.
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    // Освобождаем не только поля, но и контроллер с его сокетом,
    // подпиской и таймером. Иначе callbacks продолжат работу после ухода.
    _controller.dispose();
    _address.dispose();
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  void _generate() {
    // validate вызывает валидаторы TextFormField и показывает их ошибки.
    // После успеха int.parse безопасен; trim удаляет пробелы по краям.
    if (!_form.currentState!.validate()) return;
    // Скрываем экранную клавиатуру, чтобы результат был виден.
    FocusScope.of(context).unfocus();
    _controller.generate(
        int.parse(_minimum.text.trim()), int.parse(_maximum.text.trim()));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // notifyListeners в контроллере приводит к повторному builder.
        // Перерисовка не создаёт контроллер и сокет заново.
        listenable: _controller,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(title: const Text('Генератор чисел')),
            // SafeArea учитывает системные панели, прокрутка помогает
            // на маленьком экране и при открытой клавиатуре.
            body: SafeArea(
                child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                  child: ConstrainedBox(
                // На широком экране форма не растягивается сверх 640 px.
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Лабораторная № 2 · Вариант 6',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 16),
                      // Карточки получают данные и callbacks через параметры.
                      // Они не владеют состоянием бизнес-логики.
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
