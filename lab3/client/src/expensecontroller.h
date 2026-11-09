// Свойства и действия, доступные интерфейсу QML. Контроллер связывает UI и сервисы. Сначала данные
// проверяются/сохраняются, затем выполняется обмен; сигналы уведомляют UI о новом состоянии. UI не
// должен дублировать сетевой протокол.
// Защищаем заголовок от повторного включения в одну единицу компиляции. Интерфейс может подключаться
// несколькими исходниками.
#pragma once
#include "apiclient.h"
#include "localstore.h"
#include "pushservice.h"
#include <QSettings>
#include <QTimer>
#include <QVariantList>

// Единственная точка действий UI: QML не разбирает HTTP и не выполняет SQL.
class ExpenseController : public QObject {
    // Метаобъектная система Qt обеспечивает сигналы, свойства и вызовы из QML. Вспомогательный код
    // генерирует moc при сборке.
    Q_OBJECT
    // Свойство expenses видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение
    // после изменения.
    Q_PROPERTY(QVariantList expenses READ expenses NOTIFY changed)
    // Свойство pendingCount видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение
    // после изменения.
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY changed)
    // Свойство status видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение после
    // изменения.
    Q_PROPERTY(QString status READ status NOTIFY changed)
    // Свойство busy видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение после
    // изменения.
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    // Свойство authenticated видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать
    // значение после изменения.
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY changed)
    // Свойство offline видно в QML. READ задаёт getter, WRITE — setter, NOTIFY сообщает привязкам
    // перечитать значение после изменения.
    Q_PROPERTY(bool offline READ offline WRITE setOffline NOTIFY changed)
    // Свойство serverUrl видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение
    // после изменения.
    Q_PROPERTY(QString serverUrl READ serverUrl NOTIFY changed)
    // Свойство username видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение
    // после изменения.
    Q_PROPERTY(QString username READ username NOTIFY changed)
    // Свойство certificatePath видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать
    // значение после изменения.
    Q_PROPERTY(QString certificatePath READ certificatePath NOTIFY changed)
    // Свойство conflictInfo видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение
    // после изменения.
    Q_PROPERTY(QVariantMap conflictInfo READ conflictInfo NOTIFY changed)
    // Свойство pushStatus видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение
    // после изменения.
    Q_PROPERTY(QString pushStatus READ pushStatus NOTIFY changed)
    // Свойство lastPush видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение
    // после изменения.
    Q_PROPERTY(QString lastPush READ lastPush NOTIFY changed)
    // Свойство pushCount видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение
    // после изменения.
    Q_PROPERTY(int pushCount READ pushCount NOTIFY changed)
    // Свойство backend видно в QML. READ задаёт getter, NOTIFY сообщает привязкам перечитать значение
    // после изменения.
    Q_PROPERTY(QString backend READ backend NOTIFY changed)
// Публичный интерфейс: остальные слои используют эти действия вместо прямого изменения внутреннего
// состояния.
public:
    explicit ExpenseController(const QString &dataDir, QObject *parent = nullptr);
    ~ExpenseController() override;
    QVariantList expenses() const { return store.items().toVariantList(); }
    int pendingCount() const { return store.pending(); }
    QString status() const { return message; }
    bool busy() const { return running; }
    bool authenticated() const { return !api.token.isEmpty(); }
    bool offline() const { return offlineMode; }
    QString serverUrl() const { return api.baseUrl; }
    QString username() const { return account; }
    QString certificatePath() const { return api.certificatePath; }
    // Преобразует конфликт в QVariantMap для QML. UI сравнивает данные без самостоятельного чтения SQL.
    QVariantMap conflictInfo() const;
    QString pushStatus() const { return pushMessage; }
    QString lastPush() const { return lastEvent; }
    int pushCount() const { return eventCount; }
    QString backend() const { return lastBackend; }
    // Разрешает вызов C++-метода из QML. Экран передаёт действие контроллеру вместо собственного SQL/HTTP.
    Q_INVOKABLE void login(QString url, QString user, QString password, QString cert);
    // Разрешает вызов C++-метода из QML. Экран передаёт действие контроллеру вместо собственного SQL/HTTP.
    Q_INVOKABLE void logout();
    // Разрешает вызов C++-метода из QML. Экран передаёт действие контроллеру вместо собственного SQL/HTTP.
    Q_INVOKABLE void sync();
    // Разрешает вызов C++-метода из QML. Экран передаёт действие контроллеру вместо собственного SQL/HTTP.
    Q_INVOKABLE bool save(QString id, QString date, QString category, QString amount, QString comment);
    // Разрешает вызов C++-метода из QML. Экран передаёт действие контроллеру вместо собственного SQL/HTTP.
    Q_INVOKABLE void remove(QString id);
    // Разрешает вызов C++-метода из QML. Экран передаёт действие контроллеру вместо собственного SQL/HTTP.
    Q_INVOKABLE void resolve(bool keepLocal);
    // Меняет ручной режим и сохраняет настройку. Offline пишет только локально; возвращение online
    // запускает синхронизацию при наличии входа.
    void setOffline(bool value);
// Сигналы уведомляют подписчиков. emit не рисует UI напрямую: connect связывает событие с нужным
// обработчиком.
signals:
    void changed();
    // Только прикладное изменение, без heartbeat и статусов подключения.
    void expenseChanged(QVariantMap event);
// Внутренние детали объекта скрыты от вызывающего кода. Slots могут участвовать в системе сигналов Qt.
private:
    // HTTPS-клиент: хранит адрес, JWT и доверенный сертификат; не содержит SQL или экранных элементов.
    ApiClient api;
    // WSS-сервис: следит за постоянным соединением и событиями. Он не является вторым хранилищем данных.
    PushService push;
    // Локальная SQLite и outbox. Её данные переживают закрытие приложения.
    LocalStore store;
    // Настройки аккаунта/сервера и режима сохраняются QSettings отдельно от модели записей.
    QSettings settings;
    // Периодический/отложенный повтор. Работа таймера не должна начинать ещё одну операцию при busy.
    QTimer retry;
    // Человекочитаемый статус последней/текущей операции, который экран показывает пользователю.
    QString account, message;
    // Замок последовательности синхронизации: true не даёт начать конкурирующую операцию.
    bool running = false, offlineMode = false;
    // Запоминает push во время уже выполняющейся операции: после finish понадобится ещё одно чтение.
    bool resyncRequested = false;
    // Счётчик полученных доменных push-событий; heartbeat не должен увеличивать его.
    int eventCount = 0;
    // Исторический backend последнего REST-ответа. Не означает, что все будущие запросы попадут туда же.
    QString pushMessage, lastEvent, lastBackend;
    // Один шаг синхронизации: сначала отправка outbox, затем чтение снимка. Следующий шаг вызывается из
    // callback предыдущего — порядок сохраняется.
    void next();
    // Обрабатывает неуспешный ответ: 401 сбрасывает сессию, другие ошибки оставляют очередь для повторной
    // попытки.
    void failed(const ApiResult &result);
    // Снимает busy, обновляет сообщение и UI. Отложенная синхронизация после push запускается только после
    // завершения текущего шага.
    void finish(QString text);
    // Разделяет кэш по серверу и аккаунту. Иначе вход на другой сервер мог бы показать чужие/прежние
    // данные.
    void configureScope();
    // В offline/без JWT закрывает WSS, иначе запускает его с текущими URL, токеном и сертификатом.
    void configurePush();
};
