#include <auroraapp.h>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QDir>
#include <QDebug>
#include "expensecontroller.h"

int main(int argc, char *argv[]) {
    QScopedPointer<QGuiApplication> app(Aurora::Application::application(argc, argv));
    app->setOrganizationName("com.example");
    app->setApplicationName("expenseslab2");
    try {
        const QString data = Aurora::Application::filesDir().absolutePath();
        QDir().mkpath(data);
        ExpenseController controller(data);
        QScopedPointer<QQuickView> view(Aurora::Application::createView());
        view->rootContext()->setContextProperty("expensesController", &controller);
        view->setSource(Aurora::Application::pathTo("qml/com.example.expenseslab2.qml"));
        if (view->status() == QQuickView::Error) return 1;
        view->show();
        return app->exec();
    } catch (const std::exception &e) {
        qCritical() << "Не удалось открыть локальную базу:" << e.what();
        return 1;
    }
}
