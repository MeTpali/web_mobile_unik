// SQLite-кэш, транзакции, offline-операции и разрешение конфликтов. SQLite находится на телефоне.
// items — кэш, outbox — не подтверждённые сервером правки, validators — ETag. scope разделяет
// аккаунты/серверы. Локальное сохранение не равно сетевому успеху.
#include "localstore.h"
#include <QJsonDocument>
#include <QSqlError>
#include <QSqlQuery>
#include <QUuid>
#include <QVariant>
#include <stdexcept>

namespace {
// Превращает QJsonObject в компактные JSON-байты для SQLite. Compact удаляет форматирование, но
// сохраняет значения.
QByteArray encode(const QJsonObject &o) { return QJsonDocument(o).toJson(QJsonDocument::Compact); }
// Восстанавливает JSON-объект из столбца SQLite; кэш хранит запись как JSON целиком.
// Разбираем JSON-байты в документ Qt. Проверка ошибки и формы результата обязательна до использования
// полей.
QJsonObject decode(const QVariant &v) { return QJsonDocument::fromJson(v.toByteArray()).object(); }
// Создаёт UUID без фигурных скобок: устойчивый идентификатор записи/операции, не зависящий от позиции
// в списке.
QString uuid() { return QUuid::createUuid().toString().remove('{').remove('}'); }
// Проверяет результат SQL-команды и бросает исключение с ошибкой драйвера. Продолжать после неудачной
// записи нельзя.
void check(bool ok, const QSqlQuery &q) {
    if (!ok) throw std::runtime_error(q.lastError().text().toStdString());
}
// RAII: незавершённая транзакция откатывается даже при исключении.
class Transaction {
    // Ссылка & не копирует соединение: Transaction управляет исходным db. Оно должно жить дольше самой
    // транзакции.
    QSqlDatabase &db;
    // Пока commit не завершился успешно, деструктор обязан вызвать rollback. Флаг не позволяет откатить
    // уже сохранённые изменения.
    bool committed = false;
// Публичный интерфейс: остальные слои используют эти действия вместо прямого изменения внутреннего
// состояния.
public:
    // Конструктор сразу открывает транзакцию. explicit запрещает неявное превращение QSqlDatabase в
    // Transaction; неуспех начала вызывает исключение.
    explicit Transaction(QSqlDatabase &d) : db(d) {
        if (!db.transaction()) throw std::runtime_error(db.lastError().text().toStdString());
    }
    // Проверяем успешность commit, и только потом выставляем committed. Ошибка фиксации не должна
    // считаться сохранением.
    void commit() {
        if (!db.commit()) throw std::runtime_error(db.lastError().text().toStdString());
        committed = true;
    }
    // Деструктор вызывается при обычном выходе и раскрутке исключения. Поэтому несохранённая часть
    // операции автоматически откатывается.
    ~Transaction() { if (!committed) db.rollback(); }
};
}

// Открывает SQLite телефона и создаёт items (кэш), outbox (ожидающие операции), validators (ETag),
// если таблиц ещё нет.
LocalStore::LocalStore(const QString &path) : connectionName("expenses-" + uuid()) {
    db = QSqlDatabase::addDatabase("QSQLITE", connectionName);
    db.setDatabaseName(path);
    if (!db.open()) throw std::runtime_error(db.lastError().text().toStdString());
    QSqlQuery q(db);
    // Создаём таблицу при первом запуске. Ограничения ключей защищают целостность дополнительно к
    // проверкам приложения.
    check(q.exec("CREATE TABLE IF NOT EXISTS items(scope TEXT,id TEXT,json BLOB,PRIMARY KEY(scope,id))"), q);
    // Создаём таблицу при первом запуске. Ограничения ключей защищают целостность дополнительно к
    // проверкам приложения.
    check(q.exec("CREATE TABLE IF NOT EXISTS outbox(scope TEXT,id TEXT,json BLOB,PRIMARY KEY(scope,id))"), q);
    // Создаём таблицу при первом запуске. Ограничения ключей защищают целостность дополнительно к
    // проверкам приложения.
    check(q.exec("CREATE TABLE IF NOT EXISTS validators(scope TEXT PRIMARY KEY,etag BLOB)"), q);
}
// Закрывает БД и освобождает именованное соединение Qt. Ссылку QSqlDatabase сбрасываем до
// removeDatabase.
LocalStore::~LocalStore() {
    db.close(); db = QSqlDatabase(); QSqlDatabase::removeDatabase(connectionName);
}
// Читает текущий scope для UI, скрывает deleted и добавляет pending/conflict из outbox. Эти признаки —
// локальное состояние, не серверные поля.
QJsonArray LocalStore::items() const {
    // SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; q.next()
    // перемещает курсор, q.value(0) читает первый столбец текущей строки.
    QSqlQuery q(db); q.prepare("SELECT json FROM items WHERE scope=? ORDER BY id"); q.addBindValue(scope); check(q.exec(), q);
    QJsonArray result;
    // Перемещаем SQL-курсор к следующей строке. value(0) читает первый столбец текущего результата.
    while (q.next()) {
        auto row = decode(q.value(0));
        if (row.value("deleted").toBool()) continue;
        auto op = operation(row.value("id").toString());
        // Локальный индикатор очереди для этой строки. Он не отправляется как поле предметной записи.
        row["pending"] = !op.isEmpty();
        // Если операция содержит серверную версию, UI должен предложить сравнение/выбор вместо автоматической
        // перезаписи.
        row["conflict"] = op.contains("server");
        result.append(row);
    }
    return result;
}
// Читает одну локальную запись по scope и id. Если она отсутствует, возвращает пустой объект для
// проверки вызывающим кодом.
QJsonObject LocalStore::item(const QString &id) const {
    // SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; q.next()
    // перемещает курсор, q.value(0) читает первый столбец текущей строки.
    QSqlQuery q(db); q.prepare("SELECT json FROM items WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    // При найденной строке берём первый столбец и преобразуем в нужный тип. Иначе возвращаем пустое
    // значение без несуществующего результата.
    return q.next() ? decode(q.value(0)) : QJsonObject();
}
// С id читает операцию записи, без id — первую по rowid для последовательной отправки. Порядок нужен
// устойчивому outbox.
QJsonObject LocalStore::operation(const QString &id) const {
    QSqlQuery q(db);
    // SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; q.next()
    // перемещает курсор, q.value(0) читает первый столбец текущей строки.
    q.prepare(id.isEmpty() ? "SELECT json FROM outbox WHERE scope=? ORDER BY rowid LIMIT 1" : "SELECT json FROM outbox WHERE scope=? AND id=?");
    // Подготавливаем параметризованный SQL, затем связываем значения и проверяем выполнение.
    q.addBindValue(scope); if (!id.isEmpty()) q.addBindValue(id); check(q.exec(), q);
    // При найденной строке берём первый столбец и преобразуем в нужный тип. Иначе возвращаем пустое
    // значение без несуществующего результата.
    return q.next() ? decode(q.value(0)) : QJsonObject();
}
// Число ожидающих операций outbox текущего scope; это не количество записей на экране.
int LocalStore::pending() const {
    // SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; q.next()
    // перемещает курсор, q.value(0) читает первый столбец текущей строки.
    QSqlQuery q(db); q.prepare("SELECT count(*) FROM outbox WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q); q.next(); return q.value(0).toInt();
}
// Сохраняет JSON записи в кэше по ключу scope + id. INSERT OR REPLACE добавляет или заменяет строку.
void LocalStore::putItem(const QJsonObject &row) {
    // INSERT сохраняет строку с параметрами отдельно от SQL. Ограничения таблицы дополнительно защищают
    // данные при конкурирующих запросах.
    QSqlQuery q(db); q.prepare("INSERT OR REPLACE INTO items VALUES (?,?,?)");
    // Подготавливаем параметризованный SQL, затем связываем значения и проверяем выполнение.
    q.addBindValue(scope); q.addBindValue(row.value("id").toString()); q.addBindValue(encode(row)); check(q.exec(), q);
}
// Атомарно пишет кэш и outbox. До первой отправки правки схлопываются; после attempted тело и ключ
// менять нельзя до квитанции.
void LocalStore::enqueue(QJsonObject row, const QString &kind) {
    const auto id = row.value("id").toString();
    auto op = operation(id);
    // Уже отправленная операция могла выполниться на сервере. До квитанции нельзя изменить её тело под
    // прежним ключом; при конфликте сначала нужен выбор пользователя.
    if (op.value("attempted").toBool() || op.contains("server"))
        throw std::runtime_error("Сначала синхронизируйте ранее отправленную операцию или разрешите конфликт");
    // RAII-транзакция объединяет изменения. commit фиксирует их вместе; при исключении деструктор откатит
    // незавершённый блок.
    Transaction tx(db);
    QSqlQuery q(db);
    // До первой отправки несколько правок схлопываются в одну операцию.
    // После первой отправки её ключ и тело неизменяемы до получения квитанции.
    // Созданная offline запись ещё не уходила серверу: её локальное удаление отменяет оба изменения.
    // Отправлять сначала POST, затем DELETE не требуется.
    if (kind == "DELETE" && op.value("kind").toString() == "POST") {
        // Удаляем выбранную служебную строку/кэш текущего scope. Это не безусловное физическое удаление
        // серверной сущности.
        q.prepare("DELETE FROM items WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
        // Удаляем выбранную служебную строку/кэш текущего scope. Это не безусловное физическое удаление
        // серверной сущности.
        q.prepare("DELETE FROM outbox WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    } else {
        row["deleted"] = kind == "DELETE";
        putItem(row);
        if (op.isEmpty()) {
            op["id"] = id; op["key"] = uuid(); op["kind"] = kind; op["version"] = row.value("version");
        } else if (kind == "DELETE") op["kind"] = kind;
        op["payload"] = row;
        // INSERT сохраняет строку с параметрами отдельно от SQL. Ограничения таблицы дополнительно защищают
        // данные при конкурирующих запросах.
        q.prepare("INSERT OR REPLACE INTO outbox VALUES (?,?,?)"); q.addBindValue(scope); q.addBindValue(id); q.addBindValue(encode(op)); check(q.exec(), q);
    }
    // Фиксируем изменения блока. До commit ошибка может отменить их все, не оставляя половину обновлённого
    // кэша/очереди.
    tx.commit();
}
// Сохраняет факт отправки ДО запроса. После сбоя повтор использует прежнее тело/ключ вместо логически
// новой операции.
void LocalStore::attempted(const QString &id) {
    auto op = operation(id); op["attempted"] = true;
    // UPDATE изменяет строку внутри транзакции. Значения передаются параметрами; version/updated_at, когда
    // обновляются, позволяют обнаруживать устаревшие правки.
    QSqlQuery q(db); q.prepare("UPDATE outbox SET json=? WHERE scope=? AND id=?");
    // Подготавливаем параметризованный SQL, затем связываем значения и проверяем выполнение.
    q.addBindValue(encode(op)); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
}
// Одной транзакцией удаляет подтверждённую операцию, обновляет кэш и сбрасывает ETag, уже не
// соответствующий содержимому.
void LocalStore::acknowledge(const QString &id, const QJsonObject &server) {
    // RAII-транзакция объединяет изменения. commit фиксирует их вместе; при исключении деструктор откатит
    // незавершённый блок.
    Transaction tx(db);
    // Удаляем выбранную служебную строку/кэш текущего scope. Это не безусловное физическое удаление
    // серверной сущности.
    QSqlQuery q(db); q.prepare("DELETE FROM outbox WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    // Удаляем выбранную служебную строку/кэш текущего scope. Это не безусловное физическое удаление
    // серверной сущности.
    q.prepare("DELETE FROM validators WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    if (server.isEmpty()) {
        // Удаляем выбранную служебную строку/кэш текущего scope. Это не безусловное физическое удаление
        // серверной сущности.
        q.prepare("DELETE FROM items WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    } else putItem(server);
    // Фиксируем изменения блока. До commit ошибка может отменить их все, не оставляя половину обновлённого
    // кэша/очереди.
    tx.commit();
}
// Сохраняет серверный вариант рядом с локальной операцией, чтобы показать сравнение без потери
// пользовательской правки.
void LocalStore::conflict(const QString &id, const QJsonObject &server) {
    auto op = operation(id); op["server"] = server;
    // UPDATE изменяет строку внутри транзакции. Значения передаются параметрами; version/updated_at, когда
    // обновляются, позволяют обнаруживать устаревшие правки.
    QSqlQuery q(db); q.prepare("UPDATE outbox SET json=? WHERE scope=? AND id=?");
    // Подготавливаем параметризованный SQL, затем связываем значения и проверяем выполнение.
    q.addBindValue(encode(op)); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
}
// Принимает серверную версию или создаёт новую операцию из локальной с актуальной версией/ключом.
// Удалённая серверная сущность восстанавливается как новая с другим UUID.
void LocalStore::resolve(const QString &id, bool keepLocal) {
    auto op = operation(id);
    if (!op.contains("server")) return;
    const auto server = op.value("server").toObject();
    auto local = op.value("payload").toObject();
    // Решение и новая операция фиксируются одной транзакцией: падение между
    // ними не должно уничтожить локальную правку.
    // RAII-транзакция объединяет изменения. commit фиксирует их вместе; при исключении деструктор откатит
    // незавершённый блок.
    Transaction tx(db);
    QSqlQuery q(db);
    // Удаляем выбранную служебную строку/кэш текущего scope. Это не безусловное физическое удаление
    // серверной сущности.
    q.prepare("DELETE FROM outbox WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    putItem(server);
    if (keepLocal && !(server.value("deleted").toBool() && op.value("kind").toString() == "DELETE")) {
        QString kind = op.value("kind").toString() == "DELETE" ? "DELETE" : "PATCH";
        local["version"] = server.value("version");
        // Восстановление локальной правки поверх удалённой записи создаёт новый id: tombstone старой записи
        // остаётся частью истории синхронизации.
        if (server.value("deleted").toBool()) {
            kind = "POST"; local["id"] = uuid(); local["version"] = 0;
        }
        local["deleted"] = kind == "DELETE";
        putItem(local);
        const QJsonObject replacement{{"id", local.value("id")}, {"key", uuid()}, {"kind", kind},
                                      {"version", local.value("version")}, {"payload", local}};
        // INSERT сохраняет строку с параметрами отдельно от SQL. Ограничения таблицы дополнительно защищают
        // данные при конкурирующих запросах.
        q.prepare("INSERT INTO outbox VALUES (?,?,?)"); q.addBindValue(scope);
        // Подготавливаем параметризованный SQL, затем связываем значения и проверяем выполнение.
        q.addBindValue(local.value("id").toString()); q.addBindValue(encode(replacement)); check(q.exec(), q);
    }
    // Удаляем выбранную служебную строку/кэш текущего scope. Это не безусловное физическое удаление
    // серверной сущности.
    q.prepare("DELETE FROM validators WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    // Фиксируем изменения блока. До commit ошибка может отменить их все, не оставляя половину обновлённого
    // кэша/очереди.
    tx.commit();
}
// Заменяет кэш полным серверным снимком вместе с ETag. Разрешено только при пустом outbox, иначе
// снимок затёр бы неотправленные правки.
void LocalStore::snapshot(const QJsonArray &rows, const QByteArray &value) {
    // Вызывается только после опустошения outbox: снимок не затирает локальные правки.
    // Непустой outbox содержит локальные правки, ещё не подтверждённые сервером. Замена снимка в этот
    // момент потеряла бы их.
    if (pending()) throw std::runtime_error("Нельзя заменить кэш при непустой очереди");
    // RAII-транзакция объединяет изменения. commit фиксирует их вместе; при исключении деструктор откатит
    // незавершённый блок.
    Transaction tx(db);
    // Удаляем выбранную служебную строку/кэш текущего scope. Это не безусловное физическое удаление
    // серверной сущности.
    QSqlQuery q(db); q.prepare("DELETE FROM items WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    for (const auto &v : rows) putItem(v.toObject());
    // INSERT сохраняет строку с параметрами отдельно от SQL. Ограничения таблицы дополнительно защищают
    // данные при конкурирующих запросах.
    q.prepare("INSERT OR REPLACE INTO validators VALUES (?,?)"); q.addBindValue(scope); q.addBindValue(value); check(q.exec(), q);
    // Фиксируем изменения блока. До commit ошибка может отменить их все, не оставляя половину обновлённого
    // кэша/очереди.
    tx.commit();
}
// Читает валидатор текущего scope для If-None-Match: актуальный кэш позволяет получить 304 без JSON.
QByteArray LocalStore::etag() const {
    // SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; q.next()
    // перемещает курсор, q.value(0) читает первый столбец текущей строки.
    QSqlQuery q(db); q.prepare("SELECT etag FROM validators WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    // При найденной строке берём первый столбец и преобразуем в нужный тип. Иначе возвращаем пустое
    // значение без несуществующего результата.
    return q.next() ? q.value(0).toByteArray() : QByteArray();
}
