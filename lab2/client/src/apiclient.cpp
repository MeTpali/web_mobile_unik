#include "apiclient.h"
#include <QBuffer>
#include <QFile>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QTimer>

ApiClient::ApiClient(QObject *parent) : QObject(parent), manager(this) {}

void ApiClient::request(const QByteArray &method, const QString &path, const QJsonObject &body,
                        const QByteArray &key, int version, const QByteArray &etag,
                        std::function<void(ApiResult)> done) {
    QNetworkRequest req(QUrl(baseUrl + path));
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", "AuroraExpenses/1.0 Qt/5.6");
    if (!token.isEmpty()) req.setRawHeader("Authorization", "Bearer " + token.toUtf8());
    if (!key.isEmpty()) req.setRawHeader("Idempotency-Key", key);
    if (version > 0) req.setRawHeader("If-Match", "\"" + QByteArray::number(version) + "\"");
    if (!etag.isEmpty()) req.setRawHeader("If-None-Match", etag);
    // Добавляем конкретный учебный сертификат. Проверка имени хоста остаётся включённой.
    auto ssl = QSslConfiguration::defaultConfiguration();
    auto trusted = ssl.caCertificates();
    trusted.append(QSslCertificate::fromPath(certificatePath));
    ssl.setCaCertificates(trusted);
    req.setSslConfiguration(ssl);
    QByteArray bytes;
    if (!body.isEmpty()) {
        req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
        bytes = QJsonDocument(body).toJson(QJsonDocument::Compact);
    }
    // Перегрузка с QByteArray появилась позже Qt 5.6: используем QIODevice.
    auto *buffer = new QBuffer(&manager);
    buffer->setData(bytes);
    buffer->open(QIODevice::ReadOnly);
    auto *reply = manager.sendCustomRequest(req, method, buffer);
    buffer->setParent(reply);
    // Qt 5.6 не имеет современного setTransferTimeout: таймер отменяет весь запрос.
    auto *timer = new QTimer(reply);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, reply, [reply]() {
        reply->setProperty("timedOut", true);
        reply->abort();
    });
    timer->start(10000);
    connect(reply, &QNetworkReply::finished, this, [reply, timer, done]() {
        timer->stop();
        ApiResult result;
        result.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        result.etag = reply->rawHeader("ETag");
        result.modified = reply->rawHeader("Last-Modified");
        const auto bytes = reply->readAll();
        QJsonParseError parse;
        result.json = QJsonDocument::fromJson(bytes, &parse);
        if (reply->property("timedOut").toBool()) result.error = "Превышено время ожидания (10 с)";
        else if (result.status == 0) result.error = reply->errorString();
        else if (result.status >= 400) {
            const auto detail = result.json.object().value("detail");
            result.error = detail.isString() ? detail.toString() : "Ошибка HTTP " + QString::number(result.status);
        } else if (result.status != 204 && result.status != 304 && parse.error != QJsonParseError::NoError) {
            result.error = "Сервер вернул некорректный JSON";
        }
        reply->deleteLater();
        done(result);
    });
}
