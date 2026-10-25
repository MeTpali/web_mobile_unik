#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QString>

// Данные и очередь разделены по URL сервера и имени пользователя (scope).
class LocalStore {
public:
    explicit LocalStore(const QString &path);
    ~LocalStore();
    QString scope;
    QJsonArray items() const;
    QJsonObject item(const QString &id) const;
    QJsonObject operation(const QString &id = QString()) const;
    int pending() const;
    void enqueue(QJsonObject item, const QString &kind);
    void attempted(const QString &id);
    void acknowledge(const QString &id, const QJsonObject &server);
    void conflict(const QString &id, const QJsonObject &server);
    void resolve(const QString &id, bool keepLocal);
    void snapshot(const QJsonArray &rows, const QByteArray &etag);
    QByteArray etag() const;
private:
    QSqlDatabase db;
    QString connectionName;
    void putItem(const QJsonObject &item);
};
