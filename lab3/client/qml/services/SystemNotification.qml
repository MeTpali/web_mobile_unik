import QtQml 2.2
import Nemo.Notifications 1.0

// Системные уведомления отделены от WSS-транспорта, контроллера и экрана.
Notification {
    id: notification
    property var controller: null
    property var seen: []
    property int publishedCount: 0
    property string lastEventId: ""
    appName: "Расходы ЛР3"
    appIcon: "com.example.expenseslab3"
    expireTimeout: -1
    isTransient: false

    function notifyExpense(event) {
        var titles = {POST: "Расход добавлен", PATCH: "Расход изменён", DELETE: "Расход удалён"}
        if (!event || event.type !== "expense.changed" || !titles[event.action]) return
        if (event.event_id && seen.indexOf(event.event_id) !== -1) return
        summary = titles[event.action]
        body = "Изменения получены с сервера. Список расходов обновляется."
        previewSummary = summary
        previewBody = body
        timestamp = new Date()
        // publish сохраняет replacesId: следующие события обновляют одну запись.
        publish()
        if (replacesId) {
            lastEventId = event.event_id || ""
            if (lastEventId) {
                if (seen.length >= 128) seen.shift()
                seen.push(lastEventId)
            }
            publishedCount += 1
            console.info("System notification published: " + replacesId + " " + event.action)
        } else console.warn("Notification manager did not return an ID")
    }

    property Connections subscription: Connections {
        target: notification.controller
        onExpenseChanged: notification.notifyExpense(event)
    }
}
