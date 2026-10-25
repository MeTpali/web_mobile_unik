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
#include <stdexcept>

void require(bool ok, const char *message) { if (!ok) throw std::runtime_error(message); }
QString uuid() { return QUuid::createUuid().toString().remove('{').remove('}'); }
QJsonObject row(QString id = QString()) {
    return {{"id", id.isEmpty() ? uuid() : id}, {"date", "2026-10-25"},
            {"category", "Тест"}, {"amount_minor", 12550}, {"comment", "Qt"}, {"version", 0}};
}
void wait(std::function<bool()> condition) {
    QElapsedTimer time; time.start();
    while (!condition() && time.elapsed() < 20000) {
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
        require(c.authenticated(), "Контроллер не авторизован");
        c.setOffline(true);
        require(c.save("", "2026-10-25", "Native test", "125.50", "offline create"), "Offline создание не удалось");
        require(c.pendingCount() == 1, "Нет операции POST");
        for (auto value : c.expenses()) if (value.toMap().value("comment") == "offline create") id = value.toMap().value("id").toString();
        require(!id.isEmpty(), "Нет UUID локального расхода");
    }
    {
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
    }
    qInfo() << "PASS HTTPS native: login, offline CRUD, restart, sync, conflicts, ETag 304";
}

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    app.setOrganizationName("com.example.tests"); app.setApplicationName("expenseslab2-tests");
    QTemporaryDir tmp;
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, tmp.path());
    try {
        localTests(tmp.path() + "/local.sqlite");
        if (argc == 3) integration(argv[1], argv[2], tmp.path());
        return 0;
    } catch (const std::exception &e) { qCritical() << "FAIL" << e.what(); return 1; }
}
