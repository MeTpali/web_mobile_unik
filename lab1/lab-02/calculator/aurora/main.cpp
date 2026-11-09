// Нативная точка входа Авроры: создаёт FlutterApp и запускает цикл приложения. Импорты подключают
// зависимости; основной код выполняет одну роль в цепочке приложения.
// This file will be recreated at the next build. To avoid this, delete this line.

// Нативная точка входа запускает Flutter внутри ОС Аврора.
// Сгенерированный заголовок подключает оболочку и регистрацию плагинов.
#include "generated_plugin_registrant.h"

int main(int argc, char *argv[]) {
  // argc/argv — аргументы запуска ОС; exec запускает цикл обработки событий.
  aurora::FlutterApp app(argc, argv);
  return app.exec();
}
