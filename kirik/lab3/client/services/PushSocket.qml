// Компонент интерфейса или WebSocket-адаптер. Импорты подключают зависимости; основной код выполняет
// одну роль в цепочке приложения.
import QtQml 2.2
import QtWebSockets 1.0

// Транспортный адаптер, не экран. JWT идёт первым WSS-кадром, не в URL.
QtObject {
    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
    id: transport
    // Адрес транспортного адаптера передаётся C++-сервисом. Это endpoint WSS, не адрес файла QML.
    property string url
    // JWT нужен первому authenticate-кадру, а не отображению на странице.
    property string token
    property bool active: false
    // Сигнал передаёт событие наружу: C++-сервис подписывается на кадр или потерю соединения.
    signal textReceived(string text)
    // Сигнал передаёт событие наружу: C++-сервис подписывается на кадр или потерю соединения.
    signal lost()
    property WebSocket connection: WebSocket {
        url: transport.url
        active: transport.active
        // Реагируем на состояние WebSocket: Open начинает авторизацию, Error/Closed сообщает сервису о
        // необходимости повтора.
        onStatusChanged: {
            // При открытии отправляем JWT первым authenticate-кадром. Такой формат требует поддержки сервера;
            // токен не раскрывается в URL.
            if (status === WebSocket.Open) sendTextMessage(JSON.stringify({type: "authenticate", token: transport.token}))
            else if ((status === WebSocket.Error || status === WebSocket.Closed) && transport.active) transport.lost()
        }
        onTextMessageReceived: transport.textReceived(message)
    }
}
