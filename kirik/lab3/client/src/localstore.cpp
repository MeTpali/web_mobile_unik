#include "localstore.h"
#include <QJsonDocument>
#include <QSqlError>
#include <QSqlQuery>
#include <QUuid>
#include <QVariant>
#include <stdexcept>

namespace {
QByteArray encode(const QJsonObject &o) { return QJsonDocument(o).toJson(QJsonDocument::Compact); }
QJsonObject decode(const QVariant &v) { return QJsonDocument::fromJson(v.toByteArray()).object(); }
QString uuid() { return QUuid::createUuid().toString().remove('{').remove('}'); }
void check(bool ok, const QSqlQuery &q) {
    if (!ok) throw std::runtime_error(q.lastError().text().toStdString());
}
// RAII: незавершённая транзакция откатывается даже при исключении.
class Transaction {
    QSqlDatabase &db;
    bool committed = false;
public:
    explicit Transaction(QSqlDatabase &d) : db(d) {
        if (!db.transaction()) throw std::runtime_error(db.lastError().text().toStdString());
    }
    void commit() {
        if (!db.commit()) throw std::runtime_error(db.lastError().text().toStdString());
        committed = true;
    }
    ~Transaction() { if (!committed) db.rollback(); }
};
}

LocalStore::LocalStore(const QString &path) : connectionName("tasks-" + uuid()) {
    db = QSqlDatabase::addDatabase("QSQLITE", connectionName);
    db.setDatabaseName(path);
    if (!db.open()) throw std::runtime_error(db.lastError().text().toStdString());
    QSqlQuery q(db);
    check(q.exec("CREATE TABLE IF NOT EXISTS items(scope TEXT,id TEXT,json BLOB,PRIMARY KEY(scope,id))"), q);
    check(q.exec("CREATE TABLE IF NOT EXISTS outbox(scope TEXT,id TEXT,json BLOB,PRIMARY KEY(scope,id))"), q);
    check(q.exec("CREATE TABLE IF NOT EXISTS validators(scope TEXT PRIMARY KEY,etag BLOB)"), q);
}
LocalStore::~LocalStore() {
    db.close(); db = QSqlDatabase(); QSqlDatabase::removeDatabase(connectionName);
}
QJsonArray LocalStore::items() const {
    QSqlQuery q(db); q.prepare("SELECT json FROM items WHERE scope=? ORDER BY id"); q.addBindValue(scope); check(q.exec(), q);
    QJsonArray result;
    while (q.next()) {
        auto row = decode(q.value(0));
        if (row.value("deleted").toBool()) continue;
        auto op = operation(row.value("id").toString());
        row["pending"] = !op.isEmpty();
        row["conflict"] = op.contains("server");
        result.append(row);
    }
    return result;
}
QJsonObject LocalStore::item(const QString &id) const {
    QSqlQuery q(db); q.prepare("SELECT json FROM items WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    return q.next() ? decode(q.value(0)) : QJsonObject();
}
QJsonObject LocalStore::operation(const QString &id) const {
    QSqlQuery q(db);
    q.prepare(id.isEmpty() ? "SELECT json FROM outbox WHERE scope=? ORDER BY rowid LIMIT 1" : "SELECT json FROM outbox WHERE scope=? AND id=?");
    q.addBindValue(scope); if (!id.isEmpty()) q.addBindValue(id); check(q.exec(), q);
    return q.next() ? decode(q.value(0)) : QJsonObject();
}
int LocalStore::pending() const {
    QSqlQuery q(db); q.prepare("SELECT count(*) FROM outbox WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q); q.next(); return q.value(0).toInt();
}
void LocalStore::putItem(const QJsonObject &row) {
    QSqlQuery q(db); q.prepare("INSERT OR REPLACE INTO items VALUES (?,?,?)");
    q.addBindValue(scope); q.addBindValue(row.value("id").toString()); q.addBindValue(encode(row)); check(q.exec(), q);
}
void LocalStore::enqueue(QJsonObject row, const QString &kind) {
    const auto id = row.value("id").toString();
    auto op = operation(id);
    if (op.value("attempted").toBool() || op.contains("server"))
        throw std::runtime_error("Сначала синхронизируйте ранее отправленную операцию или разрешите конфликт");
    Transaction tx(db);
    QSqlQuery q(db);
    // До первой отправки несколько правок схлопываются в одну операцию.
    // После первой отправки её ключ и тело неизменяемы до получения квитанции.
    if (kind == "DELETE" && op.value("kind").toString() == "POST") {
        q.prepare("DELETE FROM items WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
        q.prepare("DELETE FROM outbox WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    } else {
        row["deleted"] = kind == "DELETE";
        putItem(row);
        if (op.isEmpty()) {
            op["id"] = id; op["key"] = uuid(); op["kind"] = kind; op["version"] = row.value("version");
        } else if (kind == "DELETE") op["kind"] = kind;
        op["payload"] = row;
        q.prepare("INSERT OR REPLACE INTO outbox VALUES (?,?,?)"); q.addBindValue(scope); q.addBindValue(id); q.addBindValue(encode(op)); check(q.exec(), q);
    }
    tx.commit();
}
void LocalStore::attempted(const QString &id) {
    auto op = operation(id); op["attempted"] = true;
    QSqlQuery q(db); q.prepare("UPDATE outbox SET json=? WHERE scope=? AND id=?");
    q.addBindValue(encode(op)); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
}
void LocalStore::acknowledge(const QString &id, const QJsonObject &server) {
    Transaction tx(db);
    QSqlQuery q(db); q.prepare("DELETE FROM outbox WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    q.prepare("DELETE FROM validators WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    if (server.isEmpty()) {
        q.prepare("DELETE FROM items WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    } else putItem(server);
    tx.commit();
}
void LocalStore::conflict(const QString &id, const QJsonObject &server) {
    auto op = operation(id); op["server"] = server;
    QSqlQuery q(db); q.prepare("UPDATE outbox SET json=? WHERE scope=? AND id=?");
    q.addBindValue(encode(op)); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
}
void LocalStore::resolve(const QString &id, bool keepLocal) {
    auto op = operation(id);
    if (!op.contains("server")) return;
    const auto server = op.value("server").toObject();
    auto local = op.value("payload").toObject();
    // Решение и новая операция фиксируются одной транзакцией: падение между
    // ними не должно уничтожить локальную правку.
    Transaction tx(db);
    QSqlQuery q(db);
    q.prepare("DELETE FROM outbox WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    putItem(server);
    if (keepLocal && !(server.value("deleted").toBool() && op.value("kind").toString() == "DELETE")) {
        QString kind = op.value("kind").toString() == "DELETE" ? "DELETE" : "PATCH";
        local["version"] = server.value("version");
        if (server.value("deleted").toBool()) {
            kind = "POST"; local["id"] = uuid(); local["version"] = 0;
        }
        local["deleted"] = kind == "DELETE";
        putItem(local);
        const QJsonObject replacement{{"id", local.value("id")}, {"key", uuid()}, {"kind", kind},
                                      {"version", local.value("version")}, {"payload", local}};
        q.prepare("INSERT INTO outbox VALUES (?,?,?)"); q.addBindValue(scope);
        q.addBindValue(local.value("id").toString()); q.addBindValue(encode(replacement)); check(q.exec(), q);
    }
    q.prepare("DELETE FROM validators WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    tx.commit();
}
void LocalStore::snapshot(const QJsonArray &rows, const QByteArray &value) {
    // Вызывается только после опустошения outbox: снимок не затирает локальные правки.
    if (pending()) throw std::runtime_error("Нельзя заменить кэш при непустой очереди");
    Transaction tx(db);
    QSqlQuery q(db); q.prepare("DELETE FROM items WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    for (const auto &v : rows) putItem(v.toObject());
    q.prepare("INSERT OR REPLACE INTO validators VALUES (?,?)"); q.addBindValue(scope); q.addBindValue(value); check(q.exec(), q);
    tx.commit();
}
QByteArray LocalStore::etag() const {
    QSqlQuery q(db); q.prepare("SELECT etag FROM validators WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    return q.next() ? q.value(0).toByteArray() : QByteArray();
}
