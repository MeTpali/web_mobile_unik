#pragma once
#include <QObject>
#include <QTimer>
#include <QElapsedTimer>
#include <QJsonObject>
#include <QSet>
#include <QQmlEngine>
#include <QSslConfiguration>

// WSS-транспорт отделён от UI и локального кэша. Он сообщает о событиях,
// но не применяет серверный JSON непосредственно к SQLite.
class PushService : public QObject {
    Q_OBJECT
public:
    explicit PushService(QObject *parent = nullptr);
    ~PushService() override;
    void start(const QString &url, const QString &token, const QString &certificate);
    void stop();
signals:
    void connected();
    void eventReceived(QJsonObject event);
    void statusChanged(QString status);
private slots:
    void receive(QString message);
    void schedule();
private:
    QQmlEngine *engine;
    QObject *socket = nullptr;
    QSslConfiguration initialSsl;
    QTimer retry, deadline, watchdog;
    QElapsedTimer lastMessage;
    QSet<QString> seen;
    QString baseUrl, authToken, certificatePath;
    bool wanted = false;
    int backoff = 1000;
    void open();
    void disposeSocket();
};
