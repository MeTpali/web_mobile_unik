// Интерфейс HTTP-транспорта и структура ответа. QNetworkReply работает асинхронно: request
// возвращается сразу, finished вызывает callback позже. JWT подтверждает пользователя, TLS
// подтверждает сервер и шифрует канал.
// Защищаем заголовок от повторного включения в одну единицу компиляции. Интерфейс может подключаться
// несколькими исходниками.
#pragma once
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QUrl>
#include <functional>

struct ApiResult {
    // HTTP-статус ответа. Начальный 0 обозначает отсутствие полученного HTTP-ответа, например ошибку
    // сети/TLS.
    int status = 0;
    // Разобранное тело JSON; при 204/304 оно может отсутствовать. Статус нужно учитывать до обращения к
    // полям.
    QJsonDocument json;
    // Человекочитаемая транспортная/API-ошибка. Пустая строка означает отсутствие зафиксированной ошибки.
    QString error;
    // Байты HTTP ETag. Сохраняются без изменения формата и передаются в следующий условный запрос.
    QByteArray etag;
    // Last-Modified ответа. Дополнительный валидатор времени обновления, отдельно от версии записи.
    QByteArray modified;
    // Успех — HTTP 2xx и отсутствие транспортной/JSON-ошибки. 304 обрабатывается отдельно как актуальный
    // кэш, а не обычный JSON-успех.
    bool ok() const { return status >= 200 && status < 300 && error.isEmpty(); }
};

// Транспорт не знает о виджетах, SQLite или правилах синхронизации.
class ApiClient : public QObject {
    // Метаобъектная система Qt обеспечивает сигналы, свойства и вызовы из QML. Вспомогательный код
    // генерирует moc при сборке.
    Q_OBJECT
// Публичный интерфейс: остальные слои используют эти действия вместо прямого изменения внутреннего
// состояния.
public:
    explicit ApiClient(QObject *parent = nullptr);
    // Путь к публичному доверенному сертификату, а не приватному серверному ключу.
    QString baseUrl, token, certificatePath;
    // Создаёт асинхронный HTTPS-запрос, настраивает заголовки, TLS, JSON и тайм-аут. Результат приходит
    // позже через done, не блокируя GUI.
    void request(const QByteArray &method, const QString &path, const QJsonObject &body,
                 const QByteArray &key, int version, const QByteArray &etag,
                 // done — callback, принимающий результат и ничего не возвращающий. Он выполнится после finished, когда
                 // сама request уже вернула управление UI.
                 std::function<void(ApiResult)> done);
// Внутренние детали объекта скрыты от вызывающего кода. Slots могут участвовать в системе сигналов Qt.
private:
    QNetworkAccessManager manager;
};
