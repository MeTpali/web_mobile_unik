// Асинхронный HTTPS, сертификат, заголовки, JSON и таймаут. QNetworkReply работает асинхронно: request
// возвращается сразу, finished вызывает callback позже. JWT подтверждает пользователя, TLS
// подтверждает сервер и шифрует канал.
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

// Конструктор подготавливает транспорт/таймеры. parent задаёт владение QObject: дочерние объекты
// освобождаются вместе с владельцем.
ApiClient::ApiClient(QObject *parent) : QObject(parent), manager(this) {}

// Создаёт асинхронный HTTPS-запрос, настраивает заголовки, TLS, JSON и тайм-аут. Результат приходит
// позже через done, не блокируя GUI.
void ApiClient::request(const QByteArray &method, const QString &path, const QJsonObject &body,
                        const QByteArray &key, int version, const QByteArray &etag,
                        std::function<void(ApiResult)> done) {
    QNetworkRequest req(QUrl(baseUrl + path));
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", "AuroraExpenses/1.0 Qt/5.6");
    // Bearer JWT подтверждает аккаунт. Токен не помещается в URL и не должен печататься в журнал.
    if (!token.isEmpty()) req.setRawHeader("Authorization", "Bearer " + token.toUtf8());
    // Повтор мутации использует тот же сохранённый ключ: сервер возвращает квитанцию, а не выполняет
    // операцию второй раз.
    if (!key.isEmpty()) req.setRawHeader("Idempotency-Key", key);
    // Передаём ожидаемую версию в кавычках. Несовпадение на сервере вызывает конфликт вместо потери чужой
    // правки.
    if (version > 0) req.setRawHeader("If-Match", "\"" + QByteArray::number(version) + "\"");
    // Передаём ETag кэша, чтобы получить 304 без тела, если содержимое не изменилось.
    if (!etag.isEmpty()) req.setRawHeader("If-None-Match", etag);
    // Добавляем конкретный учебный сертификат. Проверка имени хоста остаётся включённой.
    auto ssl = QSslConfiguration::defaultConfiguration();
    auto trusted = ssl.caCertificates();
    trusted.append(QSslCertificate::fromPath(certificatePath));
    // Добавляем публичный сертификат в доверие. Проверка имени/IP сохраняется, приватный ключ сервера
    // клиенту не нужен.
    ssl.setCaCertificates(trusted);
    req.setSslConfiguration(ssl);
    QByteArray bytes;
    if (!body.isEmpty()) {
        req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
        bytes = QJsonDocument(body).toJson(QJsonDocument::Compact);
    }
    // Перегрузка с QByteArray появилась позже Qt 5.6: используем QIODevice.
    // QBuffer предоставляет JSON как QIODevice для совместимой с Qt 5.6 перегрузки. Его владельцем станет
    // reply.
    auto *buffer = new QBuffer(&manager);
    buffer->setData(bytes);
    buffer->open(QIODevice::ReadOnly);
    // Запускаем асинхронный HTTP-метод. Ответ придёт через finished; здесь нет блокирующего ожидания сети.
    auto *reply = manager.sendCustomRequest(req, method, buffer);
    buffer->setParent(reply);
    // Qt 5.6 не имеет современного setTransferTimeout: таймер отменяет весь запрос.
    // Таймер ограничивает время операции в цикле событий Qt, не создавая отдельный поток.
    auto *timer = new QTimer(reply);
    timer->setSingleShot(true);
    // Связываем сигнал с обработчиком. Он сработает позже при событии, захват this обращается к текущему
    // объекту.
    connect(timer, &QTimer::timeout, reply, [reply]() {
        reply->setProperty("timedOut", true);
        // Отменяем зависший запрос; его finished затем сообщит об ошибке и завершит освобождение ресурсов.
        reply->abort();
    });
    timer->start(10000);
    // Callback выполняется после результата/ошибки. Захваты lambda сохраняют контекст запроса до прихода
    // ответа.
    connect(reply, &QNetworkReply::finished, this, [reply, timer, done]() {
        timer->stop();
        ApiResult result;
        // Берём числовой HTTP-статус из атрибута ответа Qt. Транспортная ошибка может не иметь HTTP-статуса.
        result.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        // Сохраняем непрозрачный ETag без изменения кавычек, чтобы передать его в следующем условном GET.
        result.etag = reply->rawHeader("ETag");
        result.modified = reply->rawHeader("Last-Modified");
        const auto bytes = reply->readAll();
        QJsonParseError parse;
        // Разбираем JSON-байты в документ Qt. Проверка ошибки и формы результата обязательна до использования
        // полей.
        result.json = QJsonDocument::fromJson(bytes, &parse);
        // Сначала учитываем собственный timeout, затем отсутствие HTTP, ошибочные статусы и некорректный JSON.
        // Это делает сообщение точнее.
        if (reply->property("timedOut").toBool()) result.error = "Превышено время ожидания (10 с)";
        else if (result.status == 0) result.error = reply->errorString();
        else if (result.status >= 400) {
            const auto detail = result.json.object().value("detail");
            result.error = detail.isString() ? detail.toString() : "Ошибка HTTP " + QString::number(result.status);
        } else if (result.status != 204 && result.status != 304 && parse.error != QJsonParseError::NoError) {
            result.error = "Сервер вернул некорректный JSON";
        }
        // Планируем удаление QObject через цикл событий. Удалять источник прямо во время его сигнала может
        // быть небезопасно.
        reply->deleteLater();
        done(result);
    });
}
