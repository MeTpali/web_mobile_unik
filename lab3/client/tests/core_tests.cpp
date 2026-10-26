// Проверки исполняются с настоящими Qt 5.6 и SQLite на телефоне.
#include "localstore.h"
#include "expensecontroller.h"
#include <QCoreApplication>
#include <QDate>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSettings>
#include <QTemporaryDir>
#include <QThread>
#include <QUuid>
#include <QDebug>
#include <QQmlComponent>
#include <QQmlEngine>
#include <stdexcept>

void require(bool ok, const char *message) { if (!ok) throw std::runtime_error(message); }
QString uuid() { return QUuid::createUuid().toString().remove('{').remove('}'); }
QJsonObject row(QString id = QString()) {
    return {{"id", id.isEmpty() ? uuid() : id}, {"date", "2026-10-25"},
            {"category", "Тест"}, {"amount_minor", 12550}, {"comment", "Qt"}, {"version", 0}};
}
void wait(std::function<bool()> condition) {
    QElapsedTimer time; time.start();
    while (!condition() && time.elapsed() < 30000) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20); QThread::msleep(5);
    }
    require(condition(), "Асинхронная операция не завершилась");
}
ApiResult call(ApiClient &api, QByteArray method, QString path, QJsonObject body = {}, int version = 0, QByteArray key = {}) {
    ApiResult result; bool done = false;
    api.request(method, path, body, key, version, {}, [&](ApiResult r) { result = r; done = true; });
    wait([&]() { return done; }); return result;
}

void localTests(const QString &path) {
    QString id;
    {
        LocalStore store(path); store.scope = "server\ndemo";
        auto record = row(); id = record.value("id").toString();
        store.enqueue(record, "POST"); record["comment"] = "offline edit"; store.enqueue(record, "PATCH");
        require(store.pending() == 1 && store.operation().value("kind") == "POST", "Правка POST должна схлопываться");
        store.attempted(id);
        bool rejected = false;
        try { store.enqueue(record, "PATCH"); } catch (...) { rejected = true; }
        require(rejected, "Неопределённый исход отправки должен защищать тело повтора");
        store.scope = "server\nother";
        require(store.pending() == 0 && store.items().isEmpty(), "Кэш пользователей смешан");
    }
    {
        LocalStore store(path); store.scope = "server\ndemo";
        require(store.pending() == 1 && store.operation().value("attempted").toBool(), "Очередь не пережила перезапуск");
        auto server = row(id); server["version"] = 1;
        store.acknowledge(id, server);
        require(store.pending() == 0, "Квитанция не удаляет операцию");
        auto local = server; local["comment"] = "local"; store.enqueue(local, "PATCH");
        server["version"] = 2; server["comment"] = "server";
        store.conflict(id, server); store.resolve(id, true);
        require(store.operation().value("version").toInt() == 2, "Локальная версия не перебазирована");
        require(store.item(id).value("comment") == "local", "Локальная правка потеряна");
        store.conflict(id, server); store.resolve(id, false);
        require(store.pending() == 0 && store.item(id).value("comment") == "server", "Серверная версия не принята");
        store.enqueue(local, "PATCH"); server["deleted"] = true;
        store.conflict(id, server); store.resolve(id, true);
        require(store.operation().value("kind") == "POST" && store.operation().value("id").toString() != id,
                "Восстановление удалённой записи должно создать новый UUID");
        auto pendingId = store.operation().value("id").toString();
        store.enqueue(store.item(pendingId), "DELETE");
        require(store.pending() == 0, "Удаление неотправленного создания должно отменить POST");
        store.snapshot({}, "\"empty\"");
        require(store.items().isEmpty() && store.etag() == "\"empty\"", "Снимок кэша не сохранён");
    }
    qInfo() << "PASS SQLite: offline queue, restart, isolation, conflicts, tombstones";
}

void integration(const QString &url, const QString &cert, const QString &path) {
    ApiClient api; api.baseUrl = url; api.certificatePath = cert;
    auto login = call(api, "POST", "/api/v1/auth/login", {{"username", "demo"}, {"password", "demo12345"}});
    require(login.ok(), qPrintable("HTTPS login: " + login.error));
    api.token = login.json.object().value("access_token").toString();
    QString id;
    {
        ExpenseController c(path);
        c.login(url, "demo", "demo12345", cert); wait([&]() { return !c.busy(); });
        qInfo() << "Native login done" << c.status();
        require(c.authenticated(), "Контроллер не авторизован");
        c.setOffline(true);
        qInfo() << "Offline enabled";
        require(c.save("", "2026-10-25", "Native test", "125.50", "offline create"), "Offline создание не удалось");
        require(c.pendingCount() == 1, "Нет операции POST");
        for (auto value : c.expenses()) if (value.toMap().value("comment") == "offline create") id = value.toMap().value("id").toString();
        require(!id.isEmpty(), "Нет UUID локального расхода");
        qInfo() << "Destroying first controller";
    }
    {
        qInfo() << "Restoring controller";
        ExpenseController c(path);
        require(c.offline() && c.pendingCount() == 1, "Offline состояние не пережило перезапуск");
        c.setOffline(false); wait([&]() { return !c.busy(); });
        require(c.pendingCount() == 0, qPrintable(c.status()));
        auto remote = call(api, "GET", "/api/v1/expenses/" + id);
        require(remote.ok() && remote.json.object().value("amount_minor").toInt() == 12550, "POST не дошёл до API");
        c.setOffline(true);
        require(c.save(id, "2026-10-25", "Native test", "200.01", "local conflict"), "Offline PATCH не сохранился");
        auto changed = call(api, "PATCH", "/api/v1/expenses/" + id, {{"comment", "remote conflict"}}, 1, uuid().toUtf8());
        require(changed.ok(), "Внешняя правка не выполнена");
        c.setOffline(false); wait([&]() { return !c.busy(); });
        require(!c.conflictInfo().isEmpty(), "Конфликт версий не обнаружен");
        c.resolve(true); wait([&]() { return !c.busy(); });
        require(c.pendingCount() == 0, qPrintable(c.status()));
        remote = call(api, "GET", "/api/v1/expenses/" + id);
        require(remote.json.object().value("comment") == "local conflict" && remote.json.object().value("version").toInt() == 3,
                "Выбранная локальная версия не синхронизировалась");
        c.setOffline(true); c.remove(id); require(c.pendingCount() == 1, "Offline DELETE потерян");
        c.setOffline(false); wait([&]() { return !c.busy(); });
        require(c.pendingCount() == 0 && call(api, "GET", "/api/v1/expenses/" + id).status == 404, "DELETE не дошёл до API");
        c.sync(); wait([&]() { return !c.busy(); });
        require(c.status().contains("304"), "Условный GET не использует ETag");
        wait([&]() { return c.pushStatus().startsWith("Push: "); });
        // Тот же компонент, что в приложении: проверяем реальную публикацию ОС.
        QQmlEngine notificationEngine;
        QQmlComponent notificationComponent(&notificationEngine, QUrl("qrc:/services/SystemNotification.qml"));
        QScopedPointer<QObject> notification(notificationComponent.create());
        require(!notification.isNull(), qPrintable(notificationComponent.errorString()));
        notification->setProperty("appName", "Расходы ЛР3 (тест)");
        notification->setProperty("controller", QVariant::fromValue(static_cast<QObject*>(&c)));
        qInfo() << "Native WSS authenticated:" << c.pushStatus();
        auto external = row(); external.remove("version");
        const auto externalId = external.value("id").toString();
        const auto beforePush = c.pushCount();
        require(call(api, "POST", "/api/v1/expenses", external, 0, uuid().toUtf8()).ok(), "Внешний POST не выполнен");
        auto hasExternal = [&]() {
            for (auto value : c.expenses()) if (value.toMap().value("id").toString() == externalId) return true;
            return false;
        };
        wait([&]() { return c.pushCount() > beforePush && !c.busy() && hasExternal(); });
        wait([&]() { return notification->property("publishedCount").toInt() > 0; });
        const auto notificationId = notification->property("replacesId").toUInt();
        const auto published = notification->property("publishedCount").toInt();
        require(notificationId > 0 && notification->property("summary").toString() == "Расход добавлен",
                "Системный диспетчер не подтвердил уведомление POST");
        // Повторное событие и heartbeat не должны публиковать уведомления.
        const QVariant duplicate = QVariantMap{{"type", "expense.changed"}, {"action", "POST"},
            {"event_id", notification->property("lastEventId")}};
        require(QMetaObject::invokeMethod(notification.data(), "notifyExpense", Q_ARG(QVariant, duplicate)), "Нет notifyExpense");
        const QVariant heartbeat = QVariantMap{{"type", "heartbeat"}};
        QMetaObject::invokeMethod(notification.data(), "notifyExpense", Q_ARG(QVariant, heartbeat));
        require(notification->property("publishedCount").toInt() == published, "Повтор или heartbeat создал уведомление");
        require(call(api, "PATCH", "/api/v1/expenses/" + externalId, {{"comment", "notification check"}}, 1, uuid().toUtf8()).ok(),
                "Внешний PATCH не выполнен");
        wait([&]() { return notification->property("summary").toString() == "Расход изменён"; });
        require(notification->property("replacesId").toUInt() == notificationId, "PATCH должен заменять прежнее уведомление");
        require(call(api, "DELETE", "/api/v1/expenses/" + externalId, {}, 2, uuid().toUtf8()).status == 204, "Внешний DELETE не выполнен");
        wait([&]() { return !c.busy() && !hasExternal(); });
        wait([&]() { return notification->property("summary").toString() == "Расход удалён"; });
        require(notification->property("replacesId").toUInt() == notificationId, "DELETE должен заменять прежнее уведомление");
        require(notification->property("previewSummary").toString() == "Расход удалён", "Не задан текст баннера");
        QMetaObject::invokeMethod(notification.data(), "close");
        qInfo() << "PASS system notifications: WSS POST/PATCH/DELETE, OS ID, replacement, dedup, heartbeat ignored";
        qInfo() << "PASS WSS native: external CRUD push, automatic REST refresh" << c.lastPush();
    }
    qInfo() << "PASS HTTPS native: login, offline CRUD, restart, sync, conflicts, ETag 304";
}

void watchCluster(QString url, QString cert) {
    ApiClient api; api.baseUrl = url; api.certificatePath = cert;
    auto login = call(api, "POST", "/api/v1/auth/login", {{"username", "demo"}, {"password", "demo12345"}});
    require(login.ok(), "Watch login failed");
    api.token = login.json.object().value("access_token").toString();
    PushService push;
    int connections = 0, events = 0, requests = 0, failures = 0;
    bool seenGreen = false, returnedBlue = false;
    int successesAfterReturn = 0;
    QObject::connect(&push, &PushService::connected, [&]() { ++connections; });
    QObject::connect(&push, &PushService::statusChanged, [](QString text) { qInfo() << "WATCH WS" << text; });
    QObject::connect(&push, &PushService::statusChanged, [&](QString text) {
        if (text.startsWith("Push: green")) seenGreen = true;
        if (seenGreen && text.startsWith("Push: blue")) returnedBlue = true;
    });
    QObject::connect(&push, &PushService::eventReceived, [&](QJsonObject e) {
        if (e.value("type") == "expense.changed") { ++events; qInfo() << "WATCH PUSH" << QJsonDocument(e).toJson(QJsonDocument::Compact); }
    });
    push.start(url, api.token, cert);
    QElapsedTimer duration; duration.start();
    // Монитор ждёт запуска административного сценария до 10 минут и
    // завершает проверку после возврата blue и нескольких успешных запросов.
    while (duration.elapsed() < 600000) {
        const auto r = call(api, "GET", "/api/v1/expenses");
        if (r.ok()) { ++requests; if (returnedBlue) ++successesAfterReturn; }
        else { ++failures; successesAfterReturn = 0; qWarning() << "WATCH HTTP" << r.error; }
        if (returnedBlue && successesAfterReturn >= 10 && events >= 3) break;
        QElapsedTimer pause; pause.start();
        while (pause.elapsed() < 350) { QCoreApplication::processEvents(QEventLoop::AllEvents, 20); QThread::msleep(5); }
    }
    push.stop();
    qInfo() << "WATCH RESULT requests=" << requests << "failures=" << failures << "connections=" << connections << "events=" << events;
    require(requests >= 10 && connections >= 3 && events >= 3 && returnedBlue && successesAfterReturn >= 10,
            "Native failover/blue-green recovery failed");
    qInfo() << "PASS native phone: failover, blue-green reconnect, push notifications";
}

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    app.setOrganizationName("com.example.tests"); app.setApplicationName("expenseslab3-tests");
    QTemporaryDir tmp;
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, tmp.path());
    try {
        localTests(tmp.path() + "/local.sqlite");
        if (argc == 3) integration(argv[1], argv[2], tmp.path());
        if (argc == 4 && QString(argv[3]) == "--watch") watchCluster(argv[1], argv[2]);
        return 0;
    } catch (const std::exception &e) { qCritical() << "FAIL" << e.what(); return 1; }
}
