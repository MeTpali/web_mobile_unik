import 'package:flutter/material.dart';
import 'ui/generator_page.dart';
import 'controllers/generator_controller.dart';
import 'services/random_service.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Генератор чисел',
        debugShowCheckedModeBanner: false,
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
        home: GeneratorPage(
            createController: () =>
                GeneratorController(WebSocketRandomService())),
      );
}
