#include <auroraapp.h>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QDir>
#include <QDebug>
#include "taskcontroller.h"

int main(int argc, char *argv[]) {
    QScopedPointer<QGuiApplication> app(Aurora::Application::application(argc, argv));
    app->setOrganizationName("ru.kirik");
    app->setApplicationName("taskslab3");
    try {
        const QString data = Aurora::Application::filesDir().absolutePath();
        QDir().mkpath(data);
        TaskController controller(data);
        QScopedPointer<QQuickView> view(Aurora::Application::createView());
        view->rootContext()->setContextProperty("tasksController", &controller);
        view->setSource(Aurora::Application::pathTo("qml/ru.kirik.taskslab3.qml"));
        if (view->status() == QQuickView::Error) return 1;
        view->show();
        return app->exec();
    } catch (const std::exception &e) {
        qCritical() << "Не удалось открыть локальную базу:" << e.what();
        return 1;
    }
}
