// Бизнес-правила, сессия и последовательность синхронизации. Контроллер связывает UI и сервисы.
// Сначала данные проверяются/сохраняются, затем выполняется обмен; сигналы уведомляют UI о новом
// состоянии. UI не должен дублировать сетевой протокол.
#include "expensecontroller.h"
#include <QDate>
#include <QJsonArray>
#include <QJsonObject>
#include <QRegularExpression>
#include <QUrl>
#include <QUuid>

// Конструктор восстанавливает настройки/сессию, соединяет сигналы и подготавливает повтор
// синхронизации. Один контроллер обслуживает все страницы.
ExpenseController::ExpenseController(const QString &dataDir, QObject *parent)
    : QObject(parent), api(this), push(this), store(dataDir + "/expenses.sqlite") {
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    api.baseUrl = settings.value("server", "https://192.168.0.104:9443").toString();
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    // Публичный сертификат устанавливается вместе с RPM; закрытый ключ остаётся на сервере.
    api.certificatePath = settings.value("certificate", "/usr/share/com.example.expenseslab3/certificates/server.crt").toString();
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    account = settings.value("username", "demo").toString();
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    api.token = settings.value("token").toString();
    // Восстанавливаем настройку; второй аргумент используется только при её отсутствии. Значение могло
    // сохраниться от предыдущего запуска.
    offlineMode = settings.value("offline", false).toBool();
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(&push, &PushService::statusChanged, this, [this](QString value) {
        // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
        pushMessage = value; emit changed();
    });
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(&push, &PushService::connected, this, [this]() {
        // Даже без события после переподключения запрашиваем REST-снимок.
        if (running) resyncRequested = true; else sync();
    });
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(&push, &PushService::eventReceived, this, [this](QJsonObject event) {
        if (event.value("type") == "expense.changed") {
            ++eventCount;
            lastEvent = event.value("action").toString() + " · " + event.value("instance").toString();
            emit expenseChanged(event.toVariantMap());
        }
        // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
        emit changed();
        if (running) resyncRequested = true; else sync();
    });
    configureScope();
    message = "Показаны сохранённые данные. Нажмите «Синхронизировать».";
    // Периодическая проверка работает и после реального восстановления сети.
    retry.setInterval(30000);
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(&retry, &QTimer::timeout, this, &ExpenseController::sync);
    retry.start();
    // Планируем действие на следующий проход цикла событий или после паузы. Это избегает глубокой
    // синхронной рекурсии callback-цепочки.
    QTimer::singleShot(0, this, [this]() { configurePush(); });
}

// Отключаем callbacks до разрушения полей и закрываем транспорт. Иначе сигнал деструктора мог бы
// обратиться к уже уничтоженному состоянию.
ExpenseController::~ExpenseController() {
    // Отключаем callbacks ДО разрушения строк состояния и остальных членов.
    // Иначе statusChanged из деструктора сетевого сервиса обращается к уже
    // уничтоженному QString контроллера (use-after-free).
    // Отсоединяем прежние сигналы/callbacks. Разрушение или закрытие транспорта не должно
    // вызывать обработчик уже завершающегося контроллера.
    push.disconnect(this);
    push.stop();
}

// В offline/без JWT закрывает WSS, иначе запускает его с текущими URL, токеном и сертификатом.
void ExpenseController::configurePush() {
    if (offlineMode || !authenticated()) push.stop();
    else push.start(api.baseUrl, api.token, api.certificatePath);
}

// Разделяет кэш по серверу и аккаунту. Иначе вход на другой сервер мог бы показать чужие/прежние
// данные.
void ExpenseController::configureScope() {
    store.scope = api.baseUrl + "\n" + account;
}

// Проверяет ввод, отправляет запрос входа, сохраняет сессию. При неудаче восстанавливает прежние
// параметры. Пароль не сохраняется в QSettings.
void ExpenseController::login(QString url, QString user, QString password, QString cert) {
    // Не начинаем вход во время операции или offline. Это предотвращает смену сетевых настроек посреди
    // текущей последовательности.
    if (running || offlineMode) return;
    url = url.trimmed();
    while (url.endsWith('/')) url.chop(1);
    const QUrl parsed(url);
    if (!parsed.isValid() || parsed.scheme() != "https" || parsed.host().isEmpty()
        || !parsed.userInfo().isEmpty() || !parsed.query().isEmpty() || !parsed.fragment().isEmpty()
        || (!parsed.path().isEmpty() && parsed.path() != "/")) {
        finish("Адрес должен иметь вид https://<IP-ПК>:9443"); return;
    }
    if (user.trimmed().isEmpty() || password.isEmpty()) { finish("Введите логин и пароль"); return; }
    push.stop();
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
            finish("Не удалось войти: " + result.error); configurePush(); return;
        }
        account = user.trimmed(); api.token = result.json.object().value("access_token").toString();
        // QSettings сохраняет настройку между запусками. keepUserData сохраняет её при обновлении: новый
        // default не заменит старое значение.
        settings.setValue("server", api.baseUrl); settings.setValue("certificate", api.certificatePath);
        // QSettings сохраняет настройку между запусками. keepUserData сохраняет её при обновлении: новый
        // default не заменит старое значение.
        settings.setValue("username", account); settings.setValue("token", api.token); settings.sync();
        // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
        configureScope(); configurePush(); running = false; emit changed(); sync();
    });
}

// Удаляет сессию и закрывает обмен. Кэш/outbox остаются: выход не должен уничтожать неотправленные
// правки.
void ExpenseController::logout() {
    if (running) return;
    push.stop();
    // Удаляем сессию, не кэш/очередь. Для дальнейшего обмена нужен вход, локальные правки остаются.
    api.token.clear(); settings.remove("token"); settings.sync();
    // Кэш и очередь не удаляются: повторный вход в тот же аккаунт восстановит работу.
    finish("Вы вышли. Локальные данные сохранены для следующего входа.");
}

// Меняет ручной режим и сохраняет настройку. Offline пишет только локально; возвращение online
// запускает синхронизацию при наличии входа.
void ExpenseController::setOffline(bool value) {
    if (running) return;
    // QSettings сохраняет настройку между запусками. keepUserData сохраняет её при обновлении: новый
    // default не заменит старое значение.
    offlineMode = value; settings.setValue("offline", value); settings.sync(); emit changed();
    configurePush();
    if (value) finish("Offline: изменения сохраняются только на телефоне"); else sync();
}

// Снимает busy, обновляет сообщение и UI. Отложенная синхронизация после push запускается только после
// завершения текущего шага.
void ExpenseController::finish(QString text) {
    // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
    running = false; message = text; emit changed();
    if (resyncRequested) {
        resyncRequested = false;
        // Планируем действие на следующий проход цикла событий или после паузы. Это избегает глубокой
        // синхронной рекурсии callback-цепочки.
        QTimer::singleShot(0, this, &ExpenseController::sync);
    }
}
// Обрабатывает неуспешный ответ: 401 сбрасывает сессию, другие ошибки оставляют очередь для повторной
// попытки.
void ExpenseController::failed(const ApiResult &result) {
    if (result.status == 401) {
        push.stop();
    // Удаляем сессию, не кэш/очередь. Для дальнейшего обмена нужен вход, локальные правки остаются.
    api.token.clear(); settings.remove("token"); settings.sync();
        finish("Сессия истекла. Войдите заново; очередь изменений сохранена.");
    } else finish(result.error + ". Локальные данные и очередь сохранены.");
}

// Запускает обмен только при входе, online и отсутствии другой операции. Это защищает от двух
// конкурирующих обходов outbox.
void ExpenseController::sync() {
    // Любое из условий запрещает новую синхронизацию: другая уже идёт, выбран offline или нет токена.
    // Ранний return не меняет очередь.
    if (running || offlineMode || !authenticated()) return;
    configurePush();
    // Уведомляем QML о новых значениях. Привязки перечитают свойства и обновят список/статусы/блокировки.
    running = true; message = "Синхронизация…"; emit changed();
    next();
}
// Один шаг синхронизации: сначала отправка outbox, затем чтение снимка. Следующий шаг вызывается из
// callback предыдущего — порядок сохраняется.
void ExpenseController::next() {
    try {
        const auto op = store.operation();
        if (op.contains("server")) { finish("Конфликт: выберите локальную или серверную версию"); return; }
        if (op.isEmpty()) {
            api.request("GET", "/api/v1/expenses?include_deleted=true", {}, {}, 0, store.etag(), [this](ApiResult r) {
                try {
                    // Запоминаем backend последнего REST-ответа. Следующий запрос может попасть к другому экземпляру
                    // балансировщика.
                    lastBackend = r.backendId + " · v" + r.appVersion;
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
            for (const auto &key : {"date", "category", "amount_minor", "comment"}) body[key] = payload.value(key);
            if (kind == "POST") body["id"] = id;
        }
        // Сначала фиксируем attempted в SQLite, потом отправляем сеть. Падение между ними безопасно: повтор
        // сохранит прежние ключ/тело.
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
bool ExpenseController::save(QString id, QString date, QString category, QString amount, QString comment) {
    if (running || !authenticated()) return false;
    // Разбираем календарную ISO-дату. Обратное форматирование далее проверяет, что ввод точно
    // соответствует YYYY-MM-DD.
    const auto parsedDate = QDate::fromString(date, Qt::ISODate);
    // Строгий шаблон проверяет формат строки до преобразования числа. Не любой текст, который частично
    // похож на число, допустим.
    const auto match = QRegularExpression("^([0-9]{1,10})(?:[.,]([0-9]{1,2}))?$").match(amount.trimmed());
    if (!parsedDate.isValid() || parsedDate.toString(Qt::ISODate) != date || !match.hasMatch()
        || category.trimmed().isEmpty() || category.trimmed().size() > 80 || comment.size() > 2000) {
        finish("Проверьте дату YYYY-MM-DD, категорию, сумму и длину комментария"); return false;
    }
    // Сумма переводится в целые копейки без double-округления: рубли × 100 плюс дробная часть, дополненная
    // справа нулём до двух цифр. Например 12,5 → 1250.
    const qint64 minor = match.captured(1).toLongLong() * 100 + match.captured(2).leftJustified(2, '0').toInt();
    // Проверяем положительность и верхний предел суммы уже в копейках, а не в текстовых рублях.
    if (minor <= 0 || minor > 100000000000LL) { finish("Сумма должна быть больше 0 и не больше 1 000 000 000 рублей"); return false; }
    try {
        auto row = id.isEmpty() ? QJsonObject() : store.item(id);
        // Отсутствующий id означает новую запись; существующий id сохраняет идентичность при правке.
        const bool created = id.isEmpty();
        if (created) { id = QUuid::createUuid().toString().remove('{').remove('}'); row["version"] = 0; }
        else if (row.isEmpty() || row.value("deleted").toBool()) { finish("Расход больше не существует"); return false; }
        row["id"] = id; row["date"] = date; row["category"] = category.trimmed();
        // QJson хранит числа как double; целое количество копеек в разрешённом диапазоне представляется точно.
        // Отображаемые рубли не отправляются строкой.
        row["amount_minor"] = static_cast<double>(minor); row["comment"] = comment.trimmed();
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
void ExpenseController::remove(QString id) {
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
QVariantMap ExpenseController::conflictInfo() const {
    const auto op = store.operation();
    return op.contains("server") ? op.toVariantMap() : QVariantMap();
}
// Принимает серверную версию или создаёт новую операцию из локальной с актуальной версией/ключом.
// Удалённая серверная сущность восстанавливается как новая с другим UUID.
void ExpenseController::resolve(bool keepLocal) {
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
