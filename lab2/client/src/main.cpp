// Точка входа нативного приложения и создание зависимостей. Импорты подключают зависимости; основной
// код выполняет одну роль в цепочке приложения.
#include <auroraapp.h>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QDir>
#include <QDebug>
#include "expensecontroller.h"

int main(int argc, char *argv[]) {
    // RAII-указатель удалит объект при выходе из области видимости. Порядок времени жизни важен: UI не
    // должен обращаться к уже разрушенному контроллеру.
    QScopedPointer<QGuiApplication> app(Aurora::Application::application(argc, argv));
    app->setOrganizationName("com.example");
    app->setApplicationName("expenseslab2");
    try {
        // Берём предназначенный приложению каталог данных. SQLite нельзя хранить рядом с бинарником
        // установленного пакета, который обновляется отдельно.
        const QString data = Aurora::Application::filesDir().absolutePath();
        QDir().mkpath(data);
        ExpenseController controller(data);
        // RAII-указатель удалит объект при выходе из области видимости. Порядок времени жизни важен: UI не
        // должен обращаться к уже разрушенному контроллеру.
        QScopedPointer<QQuickView> view(Aurora::Application::createView());
        // Передаём общий C++-контроллер в контекст QML. Страницы обращаются к одному объекту состояния.
        view->rootContext()->setContextProperty("expensesController", &controller);
        // Загружаем корневой QML из установленного пакета. Ошибка загрузки далее проверяется через статус
        // view, а не игнорируется.
        view->setSource(Aurora::Application::pathTo("qml/com.example.expenseslab2.qml"));
        if (view->status() == QQuickView::Error) return 1;
        // Показываем окно. Для реакции на ввод, сеть и таймеры затем нужен event loop приложения.
        view->show();
        // Цикл событий обслуживает касания, ответы сети и таймеры до завершения приложения.
        return app->exec();
    // Перехватываем ошибку SQL/валидации и переводим её в статус контроллера. RAII уже откатил
    // незавершённую транзакцию; локальные подтверждённые данные не удаляются.
    } catch (const std::exception &e) {
        qCritical() << "Не удалось открыть локальную базу:" << e.what();
        return 1;
    }
}
