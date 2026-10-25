#pragma once
#include "apiclient.h"
#include "localstore.h"
#include <QSettings>
#include <QTimer>
#include <QVariantList>

// Единственная точка действий UI: QML не разбирает HTTP и не выполняет SQL.
class ExpenseController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList expenses READ expenses NOTIFY changed)
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY changed)
    Q_PROPERTY(bool offline READ offline WRITE setOffline NOTIFY changed)
    Q_PROPERTY(QString serverUrl READ serverUrl NOTIFY changed)
    Q_PROPERTY(QString username READ username NOTIFY changed)
    Q_PROPERTY(QString certificatePath READ certificatePath NOTIFY changed)
    Q_PROPERTY(QVariantMap conflictInfo READ conflictInfo NOTIFY changed)
public:
    explicit ExpenseController(const QString &dataDir, QObject *parent = nullptr);
    QVariantList expenses() const { return store.items().toVariantList(); }
    int pendingCount() const { return store.pending(); }
    QString status() const { return message; }
    bool busy() const { return running; }
    bool authenticated() const { return !api.token.isEmpty(); }
    bool offline() const { return offlineMode; }
    QString serverUrl() const { return api.baseUrl; }
    QString username() const { return account; }
    QString certificatePath() const { return api.certificatePath; }
    QVariantMap conflictInfo() const;
    Q_INVOKABLE void login(QString url, QString user, QString password, QString cert);
    Q_INVOKABLE void logout();
    Q_INVOKABLE void sync();
    Q_INVOKABLE bool save(QString id, QString date, QString category, QString amount, QString comment);
    Q_INVOKABLE void remove(QString id);
    Q_INVOKABLE void resolve(bool keepLocal);
    void setOffline(bool value);
signals:
    void changed();
private:
    ApiClient api;
    LocalStore store;
    QSettings settings;
    QTimer retry;
    QString account, message;
    bool running = false, offlineMode = false;
    void next();
    void failed(const ApiResult &result);
    void finish(QString text);
    void configureScope();
};
