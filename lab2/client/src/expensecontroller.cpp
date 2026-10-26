#include "expensecontroller.h"
#include <QDate>
#include <QJsonArray>
#include <QJsonObject>
#include <QRegularExpression>
#include <QUrl>
#include <QUuid>

ExpenseController::ExpenseController(const QString &dataDir, QObject *parent)
    : QObject(parent), api(this), store(dataDir + "/expenses.sqlite") {
    api.baseUrl = settings.value("server", "https://10.215.223.25:8443").toString();
    api.certificatePath = settings.value("certificate", "/usr/share/com.example.expenseslab2/certificates/server.crt").toString();
    account = settings.value("username", "demo").toString();
    api.token = settings.value("token").toString();
    offlineMode = settings.value("offline", false).toBool();
    configureScope();
    message = "Показаны сохранённые данные. Нажмите «Синхронизировать».";
    // Периодическая проверка работает и после реального восстановления сети.
    retry.setInterval(30000);
    connect(&retry, &QTimer::timeout, this, &ExpenseController::sync);
    retry.start();
}

void ExpenseController::configureScope() {
    store.scope = api.baseUrl + "\n" + account;
}

void ExpenseController::login(QString url, QString user, QString password, QString cert) {
    if (running || offlineMode) return;
    url = url.trimmed();
    while (url.endsWith('/')) url.chop(1);
    const QUrl parsed(url);
    if (!parsed.isValid() || parsed.scheme() != "https" || parsed.host().isEmpty()
        || !parsed.userInfo().isEmpty() || !parsed.query().isEmpty() || !parsed.fragment().isEmpty()
        || (!parsed.path().isEmpty() && parsed.path() != "/")) {
        finish("Адрес должен иметь вид https://<IP-ПК>:8443"); return;
    }
    if (user.trimmed().isEmpty() || password.isEmpty()) { finish("Введите логин и пароль"); return; }
    running = true; message = "Вход…"; emit changed();
    const auto oldUrl = api.baseUrl, oldCert = api.certificatePath, oldToken = api.token;
    api.baseUrl = url; api.certificatePath = cert.trimmed(); api.token.clear();
    api.request("POST", "/api/v1/auth/login", {{"username", user.trimmed()}, {"password", password}}, {}, 0, {},
        [this, user, oldUrl, oldCert, oldToken](ApiResult result) {
        if (!result.ok() || !result.json.object().value("access_token").isString()) {
            api.baseUrl = oldUrl; api.certificatePath = oldCert; api.token = oldToken;
            finish("Не удалось войти: " + result.error); return;
        }
        account = user.trimmed(); api.token = result.json.object().value("access_token").toString();
        settings.setValue("server", api.baseUrl); settings.setValue("certificate", api.certificatePath);
        settings.setValue("username", account); settings.setValue("token", api.token); settings.sync();
        configureScope(); running = false; emit changed(); sync();
    });
}

void ExpenseController::logout() {
    if (running) return;
    api.token.clear(); settings.remove("token"); settings.sync();
    // Кэш и очередь не удаляются: повторный вход в тот же аккаунт восстановит работу.
    finish("Вы вышли. Локальные данные сохранены для следующего входа.");
}

void ExpenseController::setOffline(bool value) {
    if (running) return;
    offlineMode = value; settings.setValue("offline", value); settings.sync(); emit changed();
    if (value) finish("Offline: изменения сохраняются только на телефоне"); else sync();
}

void ExpenseController::finish(QString text) {
    running = false; message = text; emit changed();
}
void ExpenseController::failed(const ApiResult &result) {
    if (result.status == 401) {
        api.token.clear(); settings.remove("token"); settings.sync();
        finish("Сессия истекла. Войдите заново; очередь изменений сохранена.");
    } else finish(result.error + ". Локальные данные и очередь сохранены.");
}

void ExpenseController::sync() {
    if (running || offlineMode || !authenticated()) return;
    running = true; message = "Синхронизация…"; emit changed();
    next();
}
void ExpenseController::next() {
    try {
        const auto op = store.operation();
        if (op.contains("server")) { finish("Конфликт: выберите локальную или серверную версию"); return; }
        if (op.isEmpty()) {
            api.request("GET", "/api/v1/expenses?include_deleted=true", {}, {}, 0, store.etag(), [this](ApiResult r) {
                try {
                    if (r.status == 304) { finish("Данные актуальны (HTTP 304)"); return; }
                    if (!r.ok()) { failed(r); return; }
                    if (!r.json.isArray()) { finish("Ошибка: вместо списка получен другой JSON"); return; }
                    store.snapshot(r.json.array(), r.etag);
                    finish("Синхронизация завершена");
                } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
            });
            return;
        }
        const auto id = op.value("id").toString();
        const auto kind = op.value("kind").toString();
        const auto payload = op.value("payload").toObject();
        QJsonObject body;
        if (kind != "DELETE") {
            for (const auto &key : {"date", "category", "amount_minor", "comment"}) body[key] = payload.value(key);
            if (kind == "POST") body["id"] = id;
        }
        store.attempted(id); // Фиксируем ДО отправки: после падения повторяем то же тело и ключ.
        api.request(kind.toUtf8(), "/api/v1/expenses" + (kind == "POST" ? QString() : "/" + id), body,
                    op.value("key").toString().toUtf8(), op.value("version").toInt(), {},
                    [this, id, kind](ApiResult r) {
            try {
                if (r.status == 409) {
                    const auto server = r.json.object().value("detail").toObject().value("server").toObject();
                    if (!server.isEmpty()) store.conflict(id, server);
                    finish("Конфликт изменений. Выберите версию в блоке синхронизации."); return;
                }
                if (!r.ok()) { failed(r); return; }
                if (kind != "DELETE" && (!r.json.isObject() || r.json.object().value("id").toString() != id)) {
                    finish("Неверный ответ сервера: операция сохранена для повтора"); return;
                }
                store.acknowledge(id, kind == "DELETE" ? QJsonObject() : r.json.object());
                emit changed(); next();
            } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
        });
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
}

bool ExpenseController::save(QString id, QString date, QString category, QString amount, QString comment) {
    if (running || !authenticated()) return false;
    const auto parsedDate = QDate::fromString(date, Qt::ISODate);
    const auto match = QRegularExpression("^([0-9]{1,10})(?:[.,]([0-9]{1,2}))?$").match(amount.trimmed());
    if (!parsedDate.isValid() || parsedDate.toString(Qt::ISODate) != date || !match.hasMatch()
        || category.trimmed().isEmpty() || category.trimmed().size() > 80 || comment.size() > 2000) {
        finish("Проверьте дату YYYY-MM-DD, категорию, сумму и длину комментария"); return false;
    }
    const qint64 minor = match.captured(1).toLongLong() * 100 + match.captured(2).leftJustified(2, '0').toInt();
    if (minor <= 0 || minor > 100000000000LL) { finish("Сумма должна быть больше 0 и не больше 1 000 000 000 рублей"); return false; }
    try {
        auto row = id.isEmpty() ? QJsonObject() : store.item(id);
        const bool created = id.isEmpty();
        if (created) { id = QUuid::createUuid().toString().remove('{').remove('}'); row["version"] = 0; }
        else if (row.isEmpty() || row.value("deleted").toBool()) { finish("Расход больше не существует"); return false; }
        row["id"] = id; row["date"] = date; row["category"] = category.trimmed();
        row["amount_minor"] = static_cast<double>(minor); row["comment"] = comment.trimmed();
        store.enqueue(row, created ? "POST" : "PATCH");
        finish("Изменения сохранены на телефоне"); sync(); return true;
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); return false; }
}
void ExpenseController::remove(QString id) {
    if (running || !authenticated()) return;
    try {
        auto row = store.item(id);
        if (row.isEmpty()) return;
        store.enqueue(row, "DELETE"); finish("Удаление сохранено на телефоне"); sync();
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
}
QVariantMap ExpenseController::conflictInfo() const {
    const auto op = store.operation();
    return op.contains("server") ? op.toVariantMap() : QVariantMap();
}
void ExpenseController::resolve(bool keepLocal) {
    if (running) return;
    try {
        const auto op = store.operation();
        if (!op.contains("server")) return;
        store.resolve(op.value("id").toString(), keepLocal);
        finish("Конфликт разрешён"); sync();
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
}
