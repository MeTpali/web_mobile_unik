#pragma once
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QUrl>
#include <functional>

struct ApiResult {
    int status = 0;
    QJsonDocument json;
    QString error;
    QByteArray etag;
    QByteArray modified;
    bool ok() const { return status >= 200 && status < 300 && error.isEmpty(); }
};

// Транспорт не знает о виджетах, SQLite или правилах синхронизации.
class ApiClient : public QObject {
    Q_OBJECT
public:
    explicit ApiClient(QObject *parent = nullptr);
    QString baseUrl, token, certificatePath;
    void request(const QByteArray &method, const QString &path, const QJsonObject &body,
                 const QByteArray &key, int version, const QByteArray &etag,
                 std::function<void(ApiResult)> done);
private:
    QNetworkAccessManager manager;
};
