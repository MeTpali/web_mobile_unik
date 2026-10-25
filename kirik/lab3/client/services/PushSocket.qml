import QtQml 2.2
import QtWebSockets 1.0

// Транспортный адаптер, не экран. JWT идёт первым WSS-кадром, не в URL.
QtObject {
    id: transport
    property string url
    property string token
    property bool active: false
    signal textReceived(string text)
    signal lost()
    property WebSocket connection: WebSocket {
        url: transport.url
        active: transport.active
        onStatusChanged: {
            if (status === WebSocket.Open) sendTextMessage(JSON.stringify({type: "authenticate", token: transport.token}))
            else if ((status === WebSocket.Error || status === WebSocket.Closed) && transport.active) transport.lost()
        }
        onTextMessageReceived: transport.textReceived(message)
    }
}
