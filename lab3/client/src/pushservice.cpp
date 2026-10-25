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
PushService::PushService(QObject *parent) : QObject(parent), engine(sharedEngine()),
    initialSsl(QSslConfiguration::defaultConfiguration()) {
    retry.setSingleShot(true); deadline.setSingleShot(true);
    watchdog.setInterval(5000);
    connect(&retry, &QTimer::timeout, this, &PushService::open);
    connect(&deadline, &QTimer::timeout, this, [this]() { disposeSocket(); schedule(); });
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
void PushService::disposeSocket() {
    if (socket) {
        socket->disconnect(this);
        socket->setProperty("active", false);
        socket = nullptr;
    }
}
void PushService::stop() {
    wanted = false; retry.stop(); deadline.stop(); watchdog.stop();
    disposeSocket(); seen.clear();
    emit statusChanged("Push отключён");
}
void PushService::start(const QString &url, const QString &token, const QString &certificate) {
    if (wanted && baseUrl == url && authToken == token && certificatePath == certificate) return;
    stop(); baseUrl = url; authToken = token; certificatePath = certificate;
    wanted = true; backoff = 1000;
    // Даём закрытию прежней сессии пройти через event loop перед повторным open.
    retry.start(50);
}
void PushService::schedule() {
    deadline.stop(); watchdog.stop();
    if (!wanted || retry.isActive()) return;
    emit statusChanged(QString("Нет push-соединения. Повтор через %1 с").arg(backoff / 1000));
    retry.start(backoff); backoff = qMin(backoff * 2, 30000);
}
void PushService::open() {
    if (!wanted) return;
    disposeSocket();
    auto ssl = initialSsl;
    auto certs = ssl.caCertificates(); certs.append(QSslCertificate::fromPath(certificatePath));
    ssl.setCaCertificates(certs);
    // QML WebSocket берёт defaultConfiguration при создании. SAN проверяется.
    QSslConfiguration::setDefaultConfiguration(ssl);
    QString error;
    socket = sharedTransport(engine, error);
    if (!socket) {
        emit statusChanged("QtWebSockets недоступен: " + error);
        schedule(); return;
    }
    connect(socket, SIGNAL(textReceived(QString)), this, SLOT(receive(QString)));
    connect(socket, SIGNAL(lost()), this, SLOT(schedule()));
    QUrl url(baseUrl); url.setScheme("wss"); url.setPath("/api/v1/events");
    socket->setProperty("url", url.toString());
    socket->setProperty("token", authToken);
    emit statusChanged("Подключение push…");
    deadline.start(10000); socket->setProperty("active", true);
}
void PushService::receive(QString message) {
    lastMessage.restart();
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
