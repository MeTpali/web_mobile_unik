// Интерфейс WSS-сервиса. WSS — постоянное соединение событий. Авторизация подтверждается connected;
// уведомление приводит к REST-обновлению, а не прямой записи кадра в SQLite.
// Защищаем заголовок от повторного включения в одну единицу компиляции. Интерфейс может подключаться
// несколькими исходниками.
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
    // Метаобъектная система Qt обеспечивает сигналы, свойства и вызовы из QML. Вспомогательный код
    // генерирует moc при сборке.
    Q_OBJECT
// Публичный интерфейс: остальные слои используют эти действия вместо прямого изменения внутреннего
// состояния.
public:
    explicit PushService(QObject *parent = nullptr);
    ~PushService() override;
    // Запускает WSS с текущими URL/JWT/сертификатом. Совпадающие активные параметры не создают второе
    // соединение.
    void start(const QString &url, const QString &token, const QString &certificate);
    // Останавливает таймеры/сокет и очищает состояние доставки при offline, logout или завершении.
    void stop();
// Сигналы уведомляют подписчиков. emit не рисует UI напрямую: connect связывает событие с нужным
// обработчиком.
signals:
    void connected();
    void eventReceived(QJsonObject event);
    void statusChanged(QString status);
// Внутренние детали объекта скрыты от вызывающего кода. Slots могут участвовать в системе сигналов Qt.
private slots:
    // Разбирает кадр: connected подтверждает вход, доменные события вызывают обновление, heartbeat
    // поддерживает живость. Повторные event_id отбрасываются.
    void receive(QString message);
    // Планирует повтор с растущей паузой backoff и пределом, защищая сервер от шквала переподключений.
    void schedule();
// Внутренние детали объекта скрыты от вызывающего кода. Slots могут участвовать в системе сигналов Qt.
private:
    QQmlEngine *engine;
    QObject *socket = nullptr;
    QSslConfiguration initialSsl;
    QTimer retry, deadline, watchdog;
    // Время последнего кадра для watchdog. Отсутствие новых сообщений дольше порога означает потерю
    // живости.
    QElapsedTimer lastMessage;
    // Набор/список event_id для дедупликации событий. Ограничение размера предотвращает бесконечный рост.
    QSet<QString> seen;
    // Путь к публичному доверенному сертификату, а не приватному серверному ключу.
    QString baseUrl, authToken, certificatePath;
    bool wanted = false;
    // Пауза повтора WSS растёт после сбоя и ограничена сверху; успешный connected возвращает её к
    // начальному значению.
    int backoff = 1000;
    // Настраивает WSS/TLS и deadline для ожидания авторизованного соединения. Само открытие сокета ещё не
    // означает успешную авторизацию.
    void open();
    // Отключает сигналы старого транспорта и деактивирует его, чтобы прежние callbacks не изменили новое
    // соединение.
    void disposeSocket();
};
