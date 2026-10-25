// Корень приложения и место сборки зависимостей.
// Этот файл знает конкретный WebSocket-сервис; экран и контроллер
// работают через переданные им объекты. Это позволяет подменять сеть в тестах.
import 'package:flutter/material.dart';
import 'ui/generator_page.dart';
import 'controllers/generator_controller.dart';
import 'services/random_service.dart';

// StatelessWidget не хранит изменяемое состояние: тема и состав экрана
// определяются методом build. Состояние генератора находится в контроллере.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Генератор чисел',
        debugShowCheckedModeBanner: false,
        // Общая тема задаёт цвета и оформление всех полей ввода.
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5263DB)),
          scaffoldBackgroundColor: const Color(0xFFF4F5FA),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        // Фабрика создаёт контроллер для конкретного экземпляра экрана.
        // Экран владеет контроллером и освобождает его при dispose.
        home: GeneratorPage(
            createController: () =>
                GeneratorController(WebSocketRandomService())),
      );
}
