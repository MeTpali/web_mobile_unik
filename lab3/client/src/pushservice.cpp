// Подключение, heartbeat, безопасное завершение и повторы WSS. WSS — постоянное соединение событий.
// Авторизация подтверждается connected; уведомление приводит к REST-обновлению, а не прямой записи
// кадра в SQLite.
#include "pushservice.h"
#include <QJsonDocument>
#include <QQmlComponent>
#include <QSslCertificate>
#include <QUrl>
#include <QCoreApplication>
#include <QPointer>

namespace {
QQmlEngine *sharedEngine() {
    // Qt 5.6: движок живёт весь процесс. Пересоздание сетевых контроллеров
    // не должно уничтожать QML-движок во время работы его сетевого плагина.
    static QQmlEngine *engine = new QQmlEngine(QCoreApplication::instance());
    return engine;
}
QObject *sharedTransport(QQmlEngine *engine, QString &error) {
    // В приложении один активный контроллер. Сам сокет живёт всю сессию,
    // чтобы Qt 5.6 не разрушал QML-сетевой объект посреди SSL callbacks.
    static QPointer<QObject> transport;
    if (!transport) {
        QQmlComponent component(engine, QUrl("qrc:/services/PushSocket.qml"));
        transport = component.create();
        if (!transport) { error = component.errorString(); return nullptr; }
        QQmlEngine::setObjectOwnership(transport, QQmlEngine::CppOwnership);
        transport->setParent(engine);
    }
    return transport;
}
}

// Штатный QML-модуль QtWebSockets уже установлен на телефоне. Адаптер из
// ресурса открывает сокет; таймеры и бизнес-события обрабатывает сервис C++.
// Конструктор подготавливает транспорт/таймеры. parent задаёт владение QObject: дочерние объекты
// освобождаются вместе с владельцем.
PushService::PushService(QObject *parent) : QObject(parent), engine(sharedEngine()),
    initialSsl(QSslConfiguration::defaultConfiguration()) {
    retry.setSingleShot(true); deadline.setSingleShot(true);
    watchdog.setInterval(5000);
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(&retry, &QTimer::timeout, this, &PushService::open);
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(&deadline, &QTimer::timeout, this, [this]() { disposeSocket(); schedule(); });
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(&watchdog, &QTimer::timeout, this, [this]() {
        if (lastMessage.isValid() && lastMessage.elapsed() > 35000) { disposeSocket(); schedule(); }
    });
}
PushService::~PushService() {
    // Деструктор не сообщает пользовательское состояние: получатель сигнала
    // сам уже может находиться в процессе разрушения.
    wanted = false; retry.stop(); deadline.stop(); watchdog.stop();
    disposeSocket();
}
// Отключает сигналы старого транспорта и деактивирует его, чтобы прежние callbacks не изменили новое
// соединение.
void PushService::disposeSocket() {
    if (socket) {
        // Отсоединяем прежние сигналы/callbacks. Разрушение или закрытие транспорта не должно
        // вызывать обработчик уже завершающегося контроллера.
        socket->disconnect(this);
        socket->setProperty("active", false);
        socket = nullptr;
    }
}
// Останавливает таймеры/сокет и очищает состояние доставки при offline, logout или завершении.
void PushService::stop() {
    wanted = false; retry.stop(); deadline.stop(); watchdog.stop();
    disposeSocket(); seen.clear();
    emit statusChanged("Push отключён");
}
// Запускает WSS с текущими URL/JWT/сертификатом. Совпадающие активные параметры не создают второе
// соединение.
void PushService::start(const QString &url, const QString &token, const QString &certificate) {
    // Те же параметры уже обслуживаются: повтор sync не должен открывать дубликат WSS.
    if (wanted && baseUrl == url && authToken == token && certificatePath == certificate) return;
    stop(); baseUrl = url; authToken = token; certificatePath = certificate;
    wanted = true; backoff = 1000;
    // Даём закрытию прежней сессии пройти через event loop перед повторным open.
    retry.start(50);
}
// Планирует повтор с растущей паузой backoff и пределом, защищая сервер от шквала переподключений.
void PushService::schedule() {
    deadline.stop(); watchdog.stop();
    if (!wanted || retry.isActive()) return;
    emit statusChanged(QString("Нет push-соединения. Повтор через %1 с").arg(backoff / 1000));
    retry.start(backoff); backoff = qMin(backoff * 2, 30000);
}
// Настраивает WSS/TLS и deadline для ожидания авторизованного соединения. Само открытие сокета ещё не
// означает успешную авторизацию.
void PushService::open() {
    if (!wanted) return;
    disposeSocket();
    auto ssl = initialSsl;
    auto certs = ssl.caCertificates(); certs.append(QSslCertificate::fromPath(certificatePath));
    // Добавляем публичный сертификат в доверие. Проверка имени/IP сохраняется, приватный ключ сервера
    // клиенту не нужен.
    ssl.setCaCertificates(certs);
    // QML WebSocket берёт defaultConfiguration при создании. SAN проверяется.
    // QML WebSocket берёт настройки SSL при создании. Повторная смена глобального доверия во время HTTPS
    // нежелательна на старом Qt.
    QSslConfiguration::setDefaultConfiguration(ssl);
    // Человекочитаемая транспортная/API-ошибка. Пустая строка означает отсутствие зафиксированной ошибки.
    QString error;
    socket = sharedTransport(engine, error);
    if (!socket) {
        emit statusChanged("QtWebSockets недоступен: " + error);
        schedule(); return;
    }
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(socket, SIGNAL(textReceived(QString)), this, SLOT(receive(QString)));
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(socket, SIGNAL(lost()), this, SLOT(schedule()));
    QUrl url(baseUrl); url.setScheme("wss"); url.setPath("/api/v1/events");
    socket->setProperty("url", url.toString());
    socket->setProperty("token", authToken);
    emit statusChanged("Подключение push…");
    deadline.start(10000); socket->setProperty("active", true);
}
// Разбирает кадр: connected подтверждает вход, доменные события вызывают обновление, heartbeat
// поддерживает живость. Повторные event_id отбрасываются.
void PushService::receive(QString message) {
    lastMessage.restart();
    // Разбираем JSON-байты в документ Qt. Проверка ошибки и формы результата обязательна до использования
    // полей.
    const auto doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject()) return;
    const auto event = doc.object();
    if (event.value("type") == "connected") {
        deadline.stop(); backoff = 1000; lastMessage.start(); watchdog.start();
        emit statusChanged("Push: " + event.value("instance").toString() + " · v" + event.value("version").toString());
        emit connected(); return;
    }
    if (event.value("type") != "expense.changed" && event.value("type") != "resync") return;
    const auto id = event.value("event_id").toString();
    if (!id.isEmpty()) {
        if (seen.contains(id)) return;
        if (seen.size() >= 128) seen.clear();
        seen.insert(id);
    }
    emit eventReceived(event);
}
