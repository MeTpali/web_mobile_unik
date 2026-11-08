// Модель или интерфейс Flutter. Виджеты показывают готовое состояние и вызывают контроллер.
// Контроллеры полей хранят строки; в dispose освобождаются ресурсы. Сеть не запускается заново при
// каждом build.
import 'package:flutter/material.dart';
import '../controllers/calculator_controller.dart';

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key, required this.createController});
  final CalculatorController Function() createController;
  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  late final CalculatorController controller = widget.createController();
  // Контроллер ввода хранит строку между build. Его нужно dispose при закрытии страницы.
  final address = TextEditingController(
      text: const String.fromEnvironment('WS_URL',
          defaultValue: 'ws://192.168.0.104:8100/ws/calculate'));
  // Контроллер ввода хранит строку между build. Его нужно dispose при закрытии страницы.
  final first = TextEditingController(text: '12.5');
  // Контроллер ввода хранит строку между build. Его нужно dispose при закрытии страницы.
  final second = TextEditingController(text: '2');
  String operation = '+';

  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Освобождает подписки, таймеры и контроллеры ввода: закрытый экран не должен получать события и
  // удерживать ресурсы.
  void dispose() {
    controller.dispose();
    address.dispose();
    first.dispose();
    second.dispose();
    super.dispose();
  }

  // Настройка транспорта не занимает место на рабочем экране калькулятора.
  // Открывает настройки в нижней панели с тем же контроллером. Состояние соединения не копируется и не
  // теряется при закрытии панели.
  Future<void> showConnection() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        // Слушает контроллер и вызывает builder после notifyListeners. Так изменившиеся свойства отражаются на
        // экране.
        builder: (sheetContext) => AnimatedBuilder(
          animation: controller,
          // Отступ вокруг дочернего виджета. Меняет геометрию, не состояние и не сетевой обмен.
          builder: (context, _) => Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
            // Прокручивает форму целиком: нижние действия доступны даже с открытой клавиатурой.
            child: SingleChildScrollView(
              // Вертикальное дерево children; отступы и порядок определяют раскладку без изменения данных.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Подключение', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 20),
                  // Контроллер хранит строку поля. Тип клавиатуры лишь помогает вводу, проверка чисел выполняется
                  // отдельно.
                  TextField(
                    controller: address,
                    keyboardType: TextInputType.url,
                    decoration:
                        const InputDecoration(labelText: 'Адрес сервера'),
                  ),
                  const SizedBox(height: 20),
                  // Основное действие. null вместо onPressed отключает кнопку до подключения или на время ожидания.
                  FilledButton(
                    onPressed: controller.connecting
                        ? null
                        : () => controller.connect(address.text),
                    child: Text(controller.connecting
                        ? 'Подключение…'
                        : 'Подключиться'),
                  ),
                  const SizedBox(height: 12),
                  // Вторичное действие с обводкой использует переданный callback, не создавая отдельный сетевой сервис.
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

  // Создаёт поле числовой строки. Тип клавиатуры — подсказка, а не защита от неверного ввода.
  Widget numberField(String label, TextEditingController input) => TextField(
        controller: input,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: const TextStyle(fontSize: 28),
        decoration: InputDecoration(labelText: label, filled: true),
      );

  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Возвращает дерево Flutter для текущего состояния. Повторный build обновляет представление; сеть и
  // вычисления остаются вне виджетов.
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        // Каркас Material-экрана объединяет заголовок, фон и содержимое. Состояние вычислений живёт в
        // контроллере.
        builder: (context, _) => Scaffold(
          backgroundColor: const Color(0xfff7f5ee),
          // Верхняя панель названия и действий. Значок сети открывает настройки текущего соединения.
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
          // Вертикальная прокрутка делает форму и историю доступными при небольшой высоте/открытой клавиатуре.
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('СЧИТАЕМ ПО ПОРЯДКУ',
                  style: TextStyle(letterSpacing: 2, fontSize: 12)),
              const SizedBox(height: 16),
              // Декорация, фон и отступы области. Визуально отделяет результат от полей ввода.
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xff203931),
                  borderRadius: BorderRadius.only(
                      topRight: Radius.circular(32),
                      bottomLeft: Radius.circular(32)),
                ),
                // Вертикальное дерево children; отступы и порядок определяют раскладку без изменения данных.
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
                      // Отступ вокруг дочернего виджета. Меняет геометрию, не состояние и не сетевой обмен.
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
              // Горизонтальная группа; Expanded при необходимости распределяет доступную ширину.
              Row(
                children: [
                  for (final op in ['+', '-', '*', '/'])
                    // Занимает долю свободного места Row/Column, позволяя кнопкам/полям делить ширину экрана.
                    Expanded(
                      // Отступ вокруг дочернего виджета. Меняет геометрию, не состояние и не сетевой обмен.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        // Кнопка одного варианта: selected отражает текущую операцию, onSelected меняет выбор.
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
                // Отступ вокруг дочернего виджета. Меняет геометрию, не состояние и не сетевой обмен.
                label: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Получить результат')),
              ),
              if (!controller.connected)
                // Дополнительное действие, например открытие настроек того же подключения.
                TextButton(
                    onPressed: showConnection,
                    child: const Text('Настроить подключение')),
              if (controller.error != null)
                // Отступ вокруг дочернего виджета. Меняет геометрию, не состояние и не сетевой обмен.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(controller.error!,
                      style: const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 28),
              const Text('Лента вычислений', style: TextStyle(fontSize: 22)),
              if (controller.history.isEmpty)
                // Отступ вокруг дочернего виджета. Меняет геометрию, не состояние и не сетевой обмен.
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
