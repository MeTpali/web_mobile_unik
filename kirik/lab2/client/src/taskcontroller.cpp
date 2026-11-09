// Состояние приложения, валидация и последовательность синхронизации. Контроллер связывает UI и
// сервисы. Сначала данные проверяются/сохраняются, затем выполняется обмен; сигналы уведомляют UI о
// новом состоянии. UI не должен дублировать сетевой протокол.
#include "taskcontroller.h"
#include <QDate>
#include <QJsonArray>
#include <QJsonObject>
#include <QRegularExpression>
#include <QUrl>
#include <QUuid>

// Конструктор восстанавливает настройки/сессию, соединяет сигналы и подготавливает повтор
// синхронизации. Один контроллер обслуживает все страницы.
TaskController::TaskController(const QString &dataDir, QObject *parent)
    : QObject(parent), api(this), store(dataDir + "/tasks.sqlite") {
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    api.baseUrl = settings.value("server", "https://172.20.10.14:8543").toString();
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    // Публичный сертификат устанавливается вместе с RPM; закрытый ключ остаётся на сервере.
    api.certificatePath = settings.value("certificate", "/usr/share/ru.kirik.taskslab2/certificates/server.crt").toString();
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    account = settings.value("username", "demo").toString();
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    api.token = settings.value("token").toString();
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    offlineMode = settings.value("offline", false).toBool();
    configureScope();
    message = "Показаны сохранённые данные. Нажмите «Синхронизировать».";
    // Периодическая проверка работает и после реального восстановления сети.
    retry.setInterval(30000);
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(&retry, &QTimer::timeout, this, &TaskController::sync);
    retry.start();
}

// Разделяет кэш по серверу и аккаунту. Иначе вход на другой сервер мог бы показать чужие/прежние
// данные.
void TaskController::configureScope() {
    store.scope = api.baseUrl + "\n" + account;
}

// Проверяет ввод, отправляет запрос входа, сохраняет сессию. При неудаче восстанавливает прежние
// параметры. Пароль не сохраняется в QSettings.
void TaskController::login(QString url, QString user, QString password, QString cert) {
    // Не начинаем вход во время операции или offline. Это предотвращает смену сетевых настроек посреди
    // текущей последовательности.
    if (running || offlineMode) return;
    url = url.trimmed();
    while (url.endsWith('/')) url.chop(1);
    const QUrl parsed(url);
    if (!parsed.isValid() || parsed.scheme() != "https" || parsed.host().isEmpty()
        || !parsed.userInfo().isEmpty() || !parsed.query().isEmpty() || !parsed.fragment().isEmpty()
        || (!parsed.path().isEmpty() && parsed.path() != "/")) {
        finish("Адрес должен иметь вид https://<IP-ПК>:8543"); return;
    }
    if (user.trimmed().isEmpty() || password.isEmpty()) { finish("Введите логин и пароль"); return; }
    // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
    running = true; message = "Вход…"; emit changed();
    // Сохраняем прежнюю сессию до входа: неверный адрес/пароль не должны безвозвратно уничтожить
    // работавшую конфигурацию.
    const auto oldUrl = api.baseUrl, oldCert = api.certificatePath, oldToken = api.token;
    api.baseUrl = url; api.certificatePath = cert.trimmed(); api.token.clear();
    api.request("POST", "/api/v1/auth/login", {{"username", user.trimmed()}, {"password", password}}, {}, 0, {},
        [this, user, oldUrl, oldCert, oldToken](ApiResult result) {
        if (!result.ok() || !result.json.object().value("access_token").isString()) {
            api.baseUrl = oldUrl; api.certificatePath = oldCert; api.token = oldToken;
            finish("Не удалось войти: " + result.error); return;
        }
        account = user.trimmed(); api.token = result.json.object().value("access_token").toString();
        // QSettings сохраняет настройку между запусками. keepUserData сохраняет её при обновлении: новый
        // default не заменит старое значение.
        settings.setValue("server", api.baseUrl); settings.setValue("certificate", api.certificatePath);
        // QSettings сохраняет настройку между запусками. keepUserData сохраняет её при обновлении: новый
        // default не заменит старое значение.
        settings.setValue("username", account); settings.setValue("token", api.token); settings.sync();
        // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
        configureScope(); running = false; emit changed(); sync();
    });
}

// Удаляет сессию и закрывает обмен. Кэш/outbox остаются: выход не должен уничтожать неотправленные
// правки.
void TaskController::logout() {
    if (running) return;
    // Удаляем сессию, не кэш/очередь. Для дальнейшего обмена нужен вход, локальные правки остаются.
    api.token.clear(); settings.remove("token"); settings.sync();
    // Кэш и очередь не удаляются: повторный вход в тот же аккаунт восстановит работу.
    finish("Вы вышли. Локальные данные сохранены для следующего входа.");
}

// Меняет ручной режим и сохраняет настройку. Offline пишет только локально; возвращение online
// запускает синхронизацию при наличии входа.
void TaskController::setOffline(bool value) {
    if (running) return;
    // QSettings сохраняет настройку между запусками. keepUserData сохраняет её при обновлении: новый
    // default не заменит старое значение.
    offlineMode = value; settings.setValue("offline", value); settings.sync(); emit changed();
    if (value) finish("Offline: изменения сохраняются только на телефоне"); else sync();
}

// Снимает busy, обновляет сообщение и UI. Отложенная синхронизация после push запускается только после
// завершения текущего шага.
void TaskController::finish(QString text) {
    // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
    running = false; message = text; emit changed();
}
// Обрабатывает неуспешный ответ: 401 сбрасывает сессию, другие ошибки оставляют очередь для повторной
// попытки.
void TaskController::failed(const ApiResult &result) {
    if (result.status == 401) {
        // Удаляем сессию, не кэш/очередь. Для дальнейшего обмена нужен вход, локальные правки остаются.
        api.token.clear(); settings.remove("token"); settings.sync();
        finish("Сессия истекла. Войдите заново; очередь изменений сохранена.");
    } else finish(result.error + ". Локальные данные и очередь сохранены.");
}

// Запускает обмен только при входе, online и отсутствии другой операции. Это защищает от двух
// конкурирующих обходов outbox.
void TaskController::sync() {
    // Любое из условий запрещает новую синхронизацию: другая уже идёт, выбран offline или нет токена.
    // Ранний return не меняет очередь.
    if (running || offlineMode || !authenticated()) return;
    // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
    running = true; message = "Синхронизация…"; emit changed();
    next();
}
// Один шаг синхронизации: сначала отправка outbox, затем чтение снимка. Следующий шаг вызывается из
// callback предыдущего — порядок сохраняется.
void TaskController::next() {
    try {
        const auto op = store.operation();
        if (op.contains("server")) { finish("Конфликт: выберите локальную или серверную версию"); return; }
        if (op.isEmpty()) {
            api.request("GET", "/api/v1/tasks?include_deleted=true", {}, {}, 0, store.etag(), [this](ApiResult r) {
                try {
                    if (r.status == 304) { finish("Данные актуальны (HTTP 304)"); return; }
                    if (!r.ok()) { failed(r); return; }
                    if (!r.json.isArray()) { finish("Ошибка: вместо списка получен другой JSON"); return; }
                    store.snapshot(r.json.array(), r.etag);
                    finish("Синхронизация завершена");
                // Перехватываем ошибку SQL/валидации и переводим её в статус контроллера. RAII уже откатил
                // незавершённую транзакцию; локальные подтверждённые данные не удаляются.
                } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
            });
            return;
        }
        const auto id = op.value("id").toString();
        const auto kind = op.value("kind").toString();
        const auto payload = op.value("payload").toObject();
        QJsonObject body;
        if (kind != "DELETE") {
            for (const auto &key : {"due_date", "title", "status", "description"}) body[key] = payload.value(key);
            if (kind == "POST") body["id"] = id;
        }
        // Сначала фиксируем attempted в SQLite, потом отправляем сеть. Падение между ними безопасно: повтор
        // сохранит прежние ключ/тело.
        store.attempted(id); // Фиксируем ДО отправки: после падения повторяем то же тело и ключ.
        api.request(kind.toUtf8(), "/api/v1/tasks" + (kind == "POST" ? QString() : "/" + id), body,
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
                // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
                emit changed(); next();
            // Перехватываем ошибку SQL/валидации и переводим её в статус контроллера. RAII уже откатил
            // незавершённую транзакцию; локальные подтверждённые данные не удаляются.
            } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
        });
    // Перехватываем ошибку SQL/валидации и переводим её в статус контроллера. RAII уже откатил
    // незавершённую транзакцию; локальные подтверждённые данные не удаляются.
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
}

// Проверяет поля, сохраняет локальную запись и outbox. bool сообщает форме, можно ли закрыться;
// локальный успех ещё не означает доставку серверу.
bool TaskController::save(QString id, QString due_date, QString title, QString state, QString description) {
    if (running || !authenticated()) return false;
    // Разбираем календарную ISO-дату. Обратное форматирование далее проверяет, что ввод точно
    // соответствует YYYY-MM-DD.
    const auto parsedDate = QDate::fromString(due_date, Qt::ISODate);
    // Валидация повторяет контракт API до записи операции в offline-очередь.
    if (!parsedDate.isValid() || parsedDate.toString(Qt::ISODate) != due_date
        || title.trimmed().isEmpty() || title.trimmed().size() > 160 || description.size() > 2000
        || (state != "todo" && state != "doing" && state != "done")) {
        finish("Проверьте срок YYYY-MM-DD, заголовок, описание и статус todo/doing/done"); return false;
    }
    try {
        auto row = id.isEmpty() ? QJsonObject() : store.item(id);
        // Отсутствующий id означает новую запись; существующий id сохраняет идентичность при правке.
        const bool created = id.isEmpty();
        if (created) { id = QUuid::createUuid().toString().remove('{').remove('}'); row["version"] = 0; }
        else if (row.isEmpty() || row.value("deleted").toBool()) { finish("Задача больше не существует"); return false; }
        row["id"] = id; row["due_date"] = due_date; row["title"] = title.trimmed();
        row["status"] = state; row["description"] = description.trimmed();
        // Локальная запись и операция сохраняются атомарно. POST создаёт, PATCH изменяет; сеть запускается
        // только после сохранения очереди.
        store.enqueue(row, created ? "POST" : "PATCH");
        finish("Изменения сохранены на телефоне"); sync(); return true;
    // Перехватываем ошибку SQL/валидации и переводим её в статус контроллера. RAII уже откатил
    // незавершённую транзакцию; локальные подтверждённые данные не удаляются.
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); return false; }
}
// Ставит удаление в локальную очередь и пытается синхронизировать. При offline запрос будет выполнен
// позже.
void TaskController::remove(QString id) {
    if (running || !authenticated()) return;
    try {
        auto row = store.item(id);
        if (row.isEmpty()) return;
        store.enqueue(row, "DELETE"); finish("Удаление сохранено на телефоне"); sync();
    // Перехватываем ошибку SQL/валидации и переводим её в статус контроллера. RAII уже откатил
    // незавершённую транзакцию; локальные подтверждённые данные не удаляются.
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
}
// Преобразует конфликт в QVariantMap для QML. UI сравнивает данные без самостоятельного чтения SQL.
QVariantMap TaskController::conflictInfo() const {
    const auto op = store.operation();
    return op.contains("server") ? op.toVariantMap() : QVariantMap();
}
// Принимает серверную версию или создаёт новую операцию из локальной с актуальной версией/ключом.
// Удалённая серверная сущность восстанавливается как новая с другим UUID.
void TaskController::resolve(bool keepLocal) {
    if (running) return;
    try {
        const auto op = store.operation();
        if (!op.contains("server")) return;
        store.resolve(op.value("id").toString(), keepLocal);
        finish("Конфликт разрешён"); sync();
    // Перехватываем ошибку SQL/валидации и переводим её в статус контроллера. RAII уже откатил
    // незавершённую транзакцию; локальные подтверждённые данные не удаляются.
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
}
